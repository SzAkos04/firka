#!/bin/zsh
# Everything that should pass before a release: the unit and UI tests in the simulator,
# then a Release build for a real iPhone (unsigned, so it needs no phone or account).
#   scripts/test.sh                      # first available iPhone simulator
#   SIM="iPhone 17" scripts/test.sh
#   FAST=1 scripts/test.sh               # unit tests only (seconds instead of minutes; no UI tests)
set -euo pipefail
cd ${0:A:h:h}
SIM=${SIM:-$(xcrun simctl list devices available | grep -m1 -oE 'iPhone[^()]*' | sed 's/ *$//')}
OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT

echo "== tests on $SIM"
xcrun simctl boot "$SIM" 2>/dev/null || true   # an already-booted simulator is fine
ONLY=(); [[ -n ${FAST:-} ]] && ONLY=(-only-testing:FirkaTests)
xcodebuild test -scheme Firka -destination "platform=iOS Simulator,name=$SIM" -derivedDataPath "$OUT/test" "${ONLY[@]}" -quiet \
  || { echo "TESTS FAILED"; exit 1; }

echo "== Release build for iPhone"
xcodebuild build -scheme Firka -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$OUT/release" \
  CODE_SIGNING_ALLOWED=NO -quiet || { echo "RELEASE BUILD FAILED"; exit 1; }

echo "OK"
