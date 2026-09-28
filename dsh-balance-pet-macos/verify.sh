#!/bin/bash
# Offline checks use their own profile and never read the user's DSH credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/dist/DSH大肥鱼桌宠.app/Contents/MacOS/DSHBalancePet"
OUT="$ROOT/build/verification"
mkdir -p "$OUT"
TEST_PROFILE="$(mktemp -d "$OUT/profile.XXXXXX")"
export DSHPET_HOME="$TEST_PROFILE"
export DSHPET_OFFLINE=1
PET_PID=""
DUPLICATE_PID=""
cleanup() {
  if [[ -n "$DUPLICATE_PID" ]]; then
    kill "$DUPLICATE_PID" 2>/dev/null || true
    wait "$DUPLICATE_PID" 2>/dev/null || true
  fi
  if [[ -n "$PET_PID" ]]; then
    kill "$PET_PID" 2>/dev/null || true
    wait "$PET_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_PROFILE"
}
trap cleanup EXIT

"$BIN" --selftest | tee "$OUT/selftest.txt"
"$BIN" --snapshot "$OUT/snapshots"
codesign --verify --strict "$ROOT/dist/DSH大肥鱼桌宠.app"
cmp "$ROOT/Resources/sprite.png" "$ROOT/../原版（Windows版）/DSH余额桌宠/sprite.png"
cmp "$ROOT/Resources/hit.mp3" "$ROOT/../原版（Windows版）/DSH余额桌宠/hit.mp3"
cmp "$ROOT/Resources/sprite.png" "$ROOT/dist/DSH大肥鱼桌宠.app/Contents/Resources/sprite.png"
cmp "$ROOT/Resources/hit.mp3" "$ROOT/dist/DSH大肥鱼桌宠.app/Contents/Resources/hit.mp3"

"$BIN" > "$TEST_PROFILE/app.log" 2>&1 &
PET_PID=$!
for attempt in {1..50}; do
  [[ -f "$TEST_PROFILE/status.json" ]] && break
  sleep 0.1
done
"$BIN" --windows > "$OUT/window-status.txt"
kill -0 "$PET_PID"
"$BIN" > "$TEST_PROFILE/duplicate.log" 2>&1 &
DUPLICATE_PID=$!
for attempt in {1..30}; do
  kill -0 "$DUPLICATE_PID" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$DUPLICATE_PID" 2>/dev/null; then
  echo 'FAIL: duplicate instance is still running' >&2
  exit 1
fi
if wait "$DUPLICATE_PID"; then
  echo 'FAIL: a duplicate instance was allowed' >&2
  exit 1
fi
DUPLICATE_PID=""
if "$BIN" --reset > "$TEST_PROFILE/reset.log" 2>&1; then
  echo 'FAIL: reset should reject a running profile' >&2
  exit 1
fi
kill "$PET_PID"
wait "$PET_PID" 2>/dev/null || true
PET_PID=""
printf '%s\n' '{"sizeIndex":2,"soundOn":false,"snapOnRelease":false,"pollSeconds":60,"originX":12,"originY":34}' > "$TEST_PROFILE/state.json"
"$BIN" --reset
[[ "$(plutil -extract sizeIndex raw "$TEST_PROFILE/state.json")" == 2 ]]
[[ "$(plutil -extract soundOn raw "$TEST_PROFILE/state.json")" == false ]]
[[ "$(plutil -extract pollSeconds raw "$TEST_PROFILE/state.json")" == 60 ]]
if plutil -extract originX raw "$TEST_PROFILE/state.json" >/dev/null 2>&1; then
  echo 'FAIL: reset left a saved origin' >&2
  exit 1
fi
echo 'PASS: bundle, original assets, offline startup, duplicate prevention, and position-only reset'
