#!/bin/bash
#
# Browser Benchmark - tests different browsers with optimization options
#
# Tests Firefox, Firefox ESR, Chromium, and Luakit with various optimization flags
# Default: 3min warmup, 2min measurement period
#
# Usage:
#   ./benchmark.sh [results_dir]                    - Run full benchmark
#   ./benchmark.sh --resume [results_dir]           - Resume incomplete benchmark
#   ./benchmark.sh --browser <name> [results_dir]   - Run only specific browser
#

set -uo pipefail

# ============================================================================
# Configuration
# ============================================================================

WARMUP_SECONDS="${WARMUP_SECONDS:-180}"
MEASURE_SECONDS="${MEASURE_SECONDS:-120}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-5}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-10}"

# URLs to test
declare -a URLS=(
    "http://homeassistant.local:8123"
    "http://homeassistant:8123/dashboard-ajpad?kiosk"
)

# Browser configurations with optimization options
# Format: name|command|env_vars
declare -a BROWSERS=(
    # Firefox variants
    "firefox|firefox --disable-webrender --disable-gpu-sandbox --kiosk --no-remote --private-window|MOZ_WEBRENDER=0 MOZ_USE_LOW_MEMORY=1"
    "firefox-esr|firefox-esr --disable-webrender --disable-gpu-sandbox --kiosk --no-remote --private-window|MOZ_WEBRENDER=0 MOZ_USE_LOW_MEMORY=1"

    # Chromium variants
    "chromium|chromium --guest --kiosk --no-sandbox --test-type --no-first-run --disable-dev-shm-usage --start-maximized --noerrdialogs|"
    "chromium-minimal|chromium --guest --kiosk --no-sandbox --test-type --no-first-run --disable-dev-shm-usage --start-maximized --noerrdialogs --single-process --disable-gpu --disable-software-rasterizer --disable-extensions --disable-background-networking --disable-sync --disable-translate --disable-default-apps --disable-component-update --disable-background-timer-throttling --memory-pressure-off|"

    # Luakit
    "luakit|luakit|WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS=1 WEBKIT_DISABLE_COMPOSITING_MODE=1"
)

# ============================================================================
# Core Functions
# ============================================================================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log_section() {
    echo ""
    echo "============================================================"
    echo "$*"
    echo "============================================================"
}

get_process_stats() {
    local pid=$1
    local cpu_sum=0
    local rss_sum=0
    local count=0

    # Get all child processes including the main process
    local pids
    pids=$(pgrep -P "$pid" 2>/dev/null || true)
    pids="$pid $pids"

    for p in $pids; do
        if [ -d "/proc/$p" ]; then
            # Read CPU and memory from /proc
            local stat rss cpu
            stat=$(cat "/proc/$p/stat" 2>/dev/null || echo "0 0")
            rss=$(awk '{print $24}' <<< "$stat")
            cpu=$(ps -p "$p" -o %cpu= 2>/dev/null || echo "0")

            cpu_sum=$(awk "BEGIN {print $cpu_sum + $cpu}")
            # RSS is in pages, convert to KB (page size is typically 4KB)
            rss_sum=$(awk "BEGIN {print $rss_sum + ($rss * 4)}")
            count=$((count + 1))
        fi
    done

    echo "$cpu_sum,$rss_sum"
}

cleanup_browser() {
    local browser_bin=$1
    log "Cleaning up any existing $browser_bin processes..."

    # Luakit needs special handling - it doesn't fork properly
    if [[ "$browser_bin" == "luakit" ]]; then
        # Kill all luakit processes aggressively (use -x for exact match only)
        pkill -9 -x luakit 2>/dev/null || true
        killall -9 luakit 2>/dev/null || true
        sleep 3
        # Double-check it's really dead
        if pgrep -x luakit >/dev/null 2>&1; then
            log "ERROR: Luakit still running after cleanup!"
            pkill -9 -x luakit 2>/dev/null || true
            sleep 1
        fi
        return 0
    fi

    # Try graceful kill first for other browsers
    killall "$browser_bin" 2>/dev/null || true

    # Extra cleanup for browsers with complex names (use -x for exact matching)
    case "$browser_bin" in
        firefox|firefox-esr)
            pkill -x firefox 2>/dev/null || true
            pkill -x firefox-esr 2>/dev/null || true
            ;;
        chromium)
            pkill -x chromium 2>/dev/null || true
            pkill -x chrome 2>/dev/null || true
            ;;
    esac

    sleep 2

    # Check if any survived, force kill if needed (use -x for exact matching)
    if pgrep -x "$browser_bin" >/dev/null 2>&1; then
        log "Some processes survived, force killing..."
        killall -9 "$browser_bin" 2>/dev/null || true
        case "$browser_bin" in
            firefox|firefox-esr)
                pkill -9 -x firefox 2>/dev/null || true
                pkill -9 -x firefox-esr 2>/dev/null || true
                ;;
            chromium)
                pkill -9 -x chromium 2>/dev/null || true
                pkill -9 -x chrome 2>/dev/null || true
                ;;
        esac
        sleep 1
    fi
}

run_single_benchmark() {
    local browser_name=$1
    local browser_cmd=$2
    local browser_env=$3
    local url=$4
    local results_dir=$5

    log "Browser: $browser_name"
    log "Command: $browser_cmd"
    log "Environment: $browser_env"
    log "URL: $url"

    # Create safe filename from URL
    local safe_url
    safe_url=$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g')

    local raw_file="${results_dir}/${browser_name}_${safe_url}_raw.csv"
    local summary_file="${results_dir}/${browser_name}_${safe_url}_summary.csv"

    # Check if browser is available
    local browser_bin
    browser_bin=$(echo "$browser_cmd" | awk '{print $1}')
    if ! command -v "$browser_bin" &> /dev/null; then
        log "ERROR: Browser '$browser_bin' not found, skipping"
        return 1
    fi

    # Clean up any existing instances before starting
    cleanup_browser "$browser_bin"

    # Start browser with environment variables and URL
    log "Starting browser..."
    local launch_cmd="env $browser_env $browser_cmd '$url'"

    # Create temp log file for browser output
    local browser_log="${results_dir}/${browser_name}_${safe_url}_browser.log"
    eval "$launch_cmd" &> "$browser_log" &
    local browser_pid=$!

    # Wait for browser to start and stabilize
    log "Waiting for browser to start (PID: $browser_pid)..."
    local wait_attempts=0
    local max_wait_attempts=15
    local startup_confirmed=false

    while [[ $wait_attempts -lt $max_wait_attempts ]]; do
        sleep 1
        wait_attempts=$((wait_attempts + 1))

        if ! kill -0 "$browser_pid" 2>/dev/null; then
            log "ERROR: Browser process died during startup (attempt $wait_attempts/$max_wait_attempts)"
            log "Last 20 lines of browser output:"
            tail -20 "$browser_log" 2>/dev/null | sed 's/^/  /' || echo "  (no log output)"
            return 1
        fi

        # Check if browser has spawned child processes (indicates successful start)
        local child_count
        child_count=$(pgrep -P "$browser_pid" 2>/dev/null | wc -l)

        # Some browsers (like luakit) may work as single process
        # Consider it started if either: has children, or has been alive for 5+ seconds
        if [[ $child_count -gt 0 ]] || [[ $wait_attempts -ge 5 ]]; then
            if [[ $child_count -gt 0 ]]; then
                log "Browser started successfully with $child_count child processes"
            else
                log "Browser started (single-process mode)"
            fi
            startup_confirmed=true
            break
        fi
    done

    if [[ "$startup_confirmed" != true ]]; then
        log "WARNING: Could not confirm browser startup after ${max_wait_attempts}s"
        log "Last 20 lines of browser output:"
        tail -20 "$browser_log" 2>/dev/null | sed 's/^/  /' || echo "  (no log output)"
        return 1
    fi

    log "Browser started (PID: $browser_pid)"
    log "Warming up for ${WARMUP_SECONDS}s..."
    sleep "$WARMUP_SECONDS"

    # Check if browser is still running after warmup
    if ! kill -0 "$browser_pid" 2>/dev/null; then
        log "ERROR: Browser died during warmup"
        return 1
    fi

    # Collect measurements
    log "Collecting measurements for ${MEASURE_SECONDS}s..."
    echo "timestamp,cpu_percent,rss_kb" > "$raw_file"

    local samples=$((MEASURE_SECONDS / SAMPLE_INTERVAL))
    local -a cpu_samples
    local -a rss_samples

    for ((i=0; i<samples; i++)); do
        if ! kill -0 "$browser_pid" 2>/dev/null; then
            log "WARNING: Browser died during measurement at sample $i"
            break
        fi

        local stats
        stats=$(get_process_stats "$browser_pid")
        local cpu rss
        cpu=$(echo "$stats" | cut -d',' -f1)
        rss=$(echo "$stats" | cut -d',' -f2)

        local timestamp
        timestamp=$(date +%s)
        echo "$timestamp,$cpu,$rss" >> "$raw_file"

        cpu_samples+=("$cpu")
        rss_samples+=("$rss")

        # Get load average
        local load
        load=$(cat /proc/loadavg | awk '{print $1}')

        sleep "$SAMPLE_INTERVAL"
    done

    # Kill browser and all child processes
    log "Stopping browser..."

    # Get all descendant processes
    local all_pids
    all_pids=$(pgrep -P "$browser_pid" 2>/dev/null || true)
    all_pids="$browser_pid $all_pids"

    # Try graceful shutdown first
    for pid in $all_pids; do
        kill "$pid" 2>/dev/null || true
    done

    sleep 3

    # Force kill any remaining processes
    for pid in $all_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            log "Force killing stubborn process: $pid"
            kill -9 "$pid" 2>/dev/null || true
        fi
    done

    # Nuclear option: kill ALL instances by name
    cleanup_browser "$browser_bin"

    log "Browser stopped, waiting ${COOLDOWN_SECONDS}s for system cleanup..."
    sleep "$COOLDOWN_SECONDS"

    # Calculate statistics
    if [ ${#cpu_samples[@]} -eq 0 ]; then
        log "ERROR: No samples collected"
        return 1
    fi

    log "Calculating statistics from ${#cpu_samples[@]} samples..."

    # Calculate mean, median, min, max for CPU and RSS
    local cpu_mean cpu_med cpu_min cpu_max
    local rss_mean rss_med rss_min rss_max

    # Sort arrays for median calculation
    IFS=$'\n' cpu_sorted=($(sort -n <<<"${cpu_samples[*]}"))
    IFS=$'\n' rss_sorted=($(sort -n <<<"${rss_samples[*]}"))
    unset IFS

    # Calculate means
    cpu_mean=$(awk 'BEGIN {sum=0} {sum+=$1} END {print sum/NR}' <<< "${cpu_samples[*]// /$'\n'}")
    rss_mean=$(awk 'BEGIN {sum=0} {sum+=$1} END {print sum/NR}' <<< "${rss_samples[*]// /$'\n'}")

    # Get medians (middle value)
    local mid=$((${#cpu_sorted[@]} / 2))
    cpu_med=${cpu_sorted[$mid]}
    rss_med=${rss_sorted[$mid]}

    # Get min/max
    cpu_min=${cpu_sorted[0]}
    cpu_max=${cpu_sorted[-1]}
    rss_min=${rss_sorted[0]}
    rss_max=${rss_sorted[-1]}

    # Convert RSS from KB to MB
    rss_mean=$(awk "BEGIN {print $rss_mean / 1024}")
    rss_med=$(awk "BEGIN {print $rss_med / 1024}")
    rss_min=$(awk "BEGIN {print $rss_min / 1024}")
    rss_max=$(awk "BEGIN {print $rss_max / 1024}")

    # Get current load average
    local load_avg
    load_avg=$(cat /proc/loadavg | awk '{print $1}')

    # Write summary
    echo "timestamp,browser,cpu_mean,cpu_med,rss_mean,rss_med,rss_min,rss_max,load_mean" > "$summary_file"
    echo "$(date +%s),$browser_name,$cpu_mean,$cpu_med,$rss_mean,$rss_med,$rss_min,$rss_max,$load_avg" >> "$summary_file"

    log "Results saved:"
    log "  Raw data: $raw_file"
    log "  Summary: $summary_file"
    log "  CPU: mean=${cpu_mean}% med=${cpu_med}%"
    log "  RSS: mean=${rss_mean}MB med=${rss_med}MB"
    log "  Load: ${load_avg}"
}

# ============================================================================
# Main Execution
# ============================================================================

main_benchmark() {
    local results_dir=$1
    local resume_mode=${2:-false}

    log_section "Browser Resource Benchmark"

    if [[ "$resume_mode" == true ]]; then
        log "RESUME MODE: Continuing previous benchmark"
    fi

    # Initial cleanup - kill any lingering browser processes
    log "Performing initial cleanup of any running browsers..."

    # Use exact matching only to avoid killing the script itself
    # Luakit needs aggressive cleanup first
    pkill -9 -x luakit 2>/dev/null || true
    killall -9 luakit 2>/dev/null || true

    # Other browsers - try graceful first
    killall firefox firefox-esr chromium chrome 2>/dev/null || true
    pkill -x firefox 2>/dev/null || true
    pkill -x firefox-esr 2>/dev/null || true
    pkill -x chromium 2>/dev/null || true
    pkill -x chrome 2>/dev/null || true
    sleep 2

    # Force kill any survivors (using exact matching)
    if pgrep -x "firefox|firefox-esr|chromium|chrome|luakit" >/dev/null 2>&1; then
        log "Some browsers still running, force killing..."
        killall -9 firefox firefox-esr chromium chrome luakit 2>/dev/null || true
        pkill -9 -x firefox 2>/dev/null || true
        pkill -9 -x firefox-esr 2>/dev/null || true
        pkill -9 -x chromium 2>/dev/null || true
        pkill -9 -x chrome 2>/dev/null || true
        pkill -9 -x luakit 2>/dev/null || true
        sleep 1
    fi

    log "Results directory: $results_dir"
    if [[ -n "${BROWSER_FILTER:-}" ]]; then
        log "Filtering to browser: $BROWSER_FILTER"
    else
        log "Browser variants to test: ${#BROWSERS[@]}"
    fi
    log "URLs to test: ${#URLS[@]}"
    log "Warmup: ${WARMUP_SECONDS}s, Measurement: ${MEASURE_SECONDS}s"
    log "Cooldown between tests: ${COOLDOWN_SECONDS}s"

    # Create results directory
    mkdir -p "$results_dir"

    # Save configuration
    if [[ "$resume_mode" != true ]] || [[ ! -f "${results_dir}/config.txt" ]]; then
        {
            echo "Browser Benchmark Configuration"
            echo "================================"
            echo "Date: $(date)"
            echo "Host: $(hostname)"
            echo "Kernel: $(uname -r)"
            echo ""
            echo "Browsers tested:"
            for browser in "${BROWSERS[@]}"; do
                echo "  - $browser"
            done
        } > "${results_dir}/config.txt"
    fi

    # Run benchmarks
    local total_tests=$((${#BROWSERS[@]} * ${#URLS[@]}))
    local current_test=0
    local completed_tests=0
    local failed_tests=0
    local skipped_tests=0

    for browser_config in "${BROWSERS[@]}"; do
        IFS='|' read -r browser_name browser_cmd browser_env <<< "$browser_config"

        # Skip if filtering by browser name
        if [[ -n "${BROWSER_FILTER:-}" ]] && [[ "$browser_name" != "$BROWSER_FILTER" ]]; then
            current_test=$((current_test + ${#URLS[@]}))
            skipped_tests=$((skipped_tests + ${#URLS[@]}))
            continue
        fi

        for url in "${URLS[@]}"; do
            current_test=$((current_test + 1))

            # Check if test already completed (for resume mode)
            local safe_url
            safe_url=$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g')
            local summary_file="${results_dir}/${browser_name}_${safe_url}_summary.csv"

            if [[ "$resume_mode" == true ]] && [[ -f "$summary_file" ]] && [[ $(wc -l < "$summary_file") -gt 1 ]]; then
                log_section "Test $current_test of $total_tests [SKIPPED - Already Complete]"
                log "Browser: $browser_name"
                log "URL: $url"
                skipped_tests=$((skipped_tests + 1))
                continue
            fi

            log_section "Test $current_test of $total_tests"

            if run_single_benchmark "$browser_name" "$browser_cmd" "$browser_env" "$url" "$results_dir"; then
                completed_tests=$((completed_tests + 1))
                log "Test completed successfully"
            else
                failed_tests=$((failed_tests + 1))
                log "Test failed - continuing with next test"
            fi
        done
    done

    # Summary of test run
    log_section "Test Run Summary"
    log "Total tests: $total_tests"
    log "Completed: $completed_tests"
    log "Failed: $failed_tests"
    if [[ "$resume_mode" == true ]] || [[ -n "${BROWSER_FILTER:-}" ]]; then
        log "Skipped: $skipped_tests"
    fi

    # Generate comparison report
    log_section "Generating Comparison Report"

    local comparison_file="${results_dir}/comparison_report.txt"
    {
        echo "============================================================"
        echo "BROWSER BENCHMARK COMPARISON"
        echo "Generated: $(date)"
        echo "============================================================"
        echo ""

        for url in "${URLS[@]}"; do
            echo ""
            echo "URL: $url"
            echo "------------------------------------------------------------"
            printf "%-18s %10s %10s %12s %10s\n" "Browser" "CPU Mean" "CPU Med" "RSS (MB)" "Load"
            printf "%-18s %10s %10s %12s %10s\n" "-------" "--------" "-------" "--------" "----"

            for browser_config in "${BROWSERS[@]}"; do
                IFS='|' read -r browser_name _ _ <<< "$browser_config"
                local safe_url
                safe_url=$(echo "$url" | sed 's/[^a-zA-Z0-9]/_/g')
                local summary_file="${results_dir}/${browser_name}_${safe_url}_summary.csv"

                if [ -f "$summary_file" ]; then
                    local data
                    data=$(tail -1 "$summary_file")
                    local cpu_mean cpu_med rss_mean load_mean
                    cpu_mean=$(echo "$data" | cut -d',' -f3)
                    cpu_med=$(echo "$data" | cut -d',' -f4)
                    rss_mean=$(echo "$data" | cut -d',' -f5)
                    load_mean=$(echo "$data" | cut -d',' -f9)

                    printf "%-18s %10.2f %10.2f %12.2f %10.3f\n" \
                        "$browser_name" "$cpu_mean" "$cpu_med" "$rss_mean" "$load_mean"
                fi
            done
        done
    } | tee "$comparison_file"

    log_section "Benchmark Complete!"
    log "Results saved to: $results_dir"
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse arguments
    RESUME_MODE=false
    RESULTS_DIR=""
    BROWSER_FILTER=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --resume)
                RESUME_MODE=true
                shift
                ;;
            --browser)
                if [[ -z "${2:-}" ]]; then
                    echo "ERROR: --browser requires a browser name" >&2
                    echo "Available browsers: firefox, firefox-esr, chromium, chromium-minimal, luakit" >&2
                    exit 1
                fi
                BROWSER_FILTER="$2"
                shift 2
                ;;
            *)
                RESULTS_DIR="$1"
                shift
                ;;
        esac
    done

    # Handle resume mode directory finding
    if [[ "$RESUME_MODE" == true ]] && [[ -z "$RESULTS_DIR" ]]; then
        # Find most recent benchmark directory
        RESULTS_DIR=$(find . -maxdepth 1 -type d -name "benchmark_*" -printf "%T@ %p\n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2)
        if [[ -z "$RESULTS_DIR" ]]; then
            echo "ERROR: No previous benchmark directory found" >&2
            exit 1
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Resuming most recent benchmark: $RESULTS_DIR"
    fi

    # Validate resume directory exists
    if [[ "$RESUME_MODE" == true ]] && [[ ! -d "$RESULTS_DIR" ]]; then
        echo "ERROR: Resume directory does not exist: $RESULTS_DIR" >&2
        exit 1
    fi

    # Set default results directory if not specified
    if [[ -z "$RESULTS_DIR" ]]; then
        RESULTS_DIR="./benchmark_$(date +%Y%m%d_%H%M%S)"
    fi

    # Export browser filter for use in main function
    export BROWSER_FILTER

    main_benchmark "$RESULTS_DIR" "$RESUME_MODE"
fi
