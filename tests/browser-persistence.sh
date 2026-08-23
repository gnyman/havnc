#!/usr/bin/env bash
set -euo pipefail

launcher="$(dirname "$0")/../config/supervisor/5-browser.conf"

assert_contains() {
  if ! grep -Fq -- "$1" "$launcher"; then
    echo "Expected browser launcher to contain: $1" >&2
    exit 1
  fi
}

assert_contains 'PERSIST_DATA=$(jq --raw-output ".persist_data // false" /data/options.json)'
assert_contains 'PROFILE_DIR=/data/browser-data/chromium'
assert_contains 'PROFILE_DIR=/data/browser-data/firefox'
assert_contains 'PROFILE_DIR=/data/browser-data/firefox-esr'
assert_contains 'XDG_DATA_HOME=/data/browser-data/luakit/data'
assert_contains 'XDG_CACHE_HOME=/data/browser-data/luakit/cache'

if grep -Eq -- 'chromium .*--guest' "$launcher"; then
  echo "Chromium guest mode prevents a persistent login" >&2
  exit 1
fi

echo "Browser persistence configuration checks passed"
