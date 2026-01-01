# Engine Benchmark

This is a simple benchmark script which was used to try to get a bit scientific testing of the various engines.

## Usage

```bash
./benchmark.sh [results_dir]                    # Run full benchmark
./benchmark.sh --resume [results_dir]           # Resume incomplete run
./benchmark.sh --browser <name> [results_dir]   # Test specific browser
```

## Configuration

Environment variables:
- `WARMUP_SECONDS` - warmup period (default: 180)
- `MEASURE_SECONDS` - measurement period (default: 120)
- `SAMPLE_INTERVAL` - sampling interval (default: 5)
- `COOLDOWN_SECONDS` - cooldown between tests (default: 10)

Edit `URLS` array in script to configure test URLs.

## Output

- `*_raw.csv` - timestamped CPU/memory samples
- `*_summary.csv` - mean/median statistics
- `comparison_report.txt` - side-by-side comparison

