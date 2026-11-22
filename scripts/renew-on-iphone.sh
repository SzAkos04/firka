#!/bin/zsh
# Re-signs and reinstalls Firka on the iPhone before the free Apple ID's 7-day signature runs out.
# launchd runs it twice a day (scripts/install-renew-schedule.sh); it does nothing until < 3 days are left.
# Manual run: scripts/renew-on-iphone.sh [other] [--force]
#   other: a second app set up in scripts/renew.local.sh, renewed with its own install command
# Personal settings live in scripts/renew.local.sh (not in git), see scripts/renew.local.example.sh.
set -uo pipefail

PROJECT_DIR=${0:A:h:h}
DEVICE=""                                # the iPhone's id, from `xcrun devicectl list devices`
OTHER_NAME="" OTHER_APP_ID="" OTHER_INSTALL=""
[[ -f ${0:A:h}/renew.local.sh ]] && source ${0:A:h}/renew.local.sh
[[ -n $DEVICE ]] || { print "Set DEVICE in scripts/renew.local.sh (see renew.local.example.sh)"; exit 1; }

# The app id and team come from the Xcode project (Config/Local.xcconfig).
settings=$(xcodebuild -project "$PROJECT_DIR/Firka.xcodeproj" -target Firka -showBuildSettings 2>/dev/null)
APP=Firka
APP_ID=$(print -r -- "$settings" | awk -F' = ' '/ PRODUCT_BUNDLE_IDENTIFIER = /{print $2; exit}')
TEAM=$(print -r -- "$settings" | awk -F' = ' '/ DEVELOPMENT_TEAM = /{print $2; exit}')
if [[ ${1:-} == other ]]; then
  [[ -n $OTHER_INSTALL ]] || exit 0      # no second app configured
  APP=$OTHER_NAME APP_ID=$OTHER_APP_ID; shift
fi
RENEW_BEFORE=$((3 * 24 * 3600))          # renew when less than this is left
PROFILES="$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"
WORK="$HOME/Library/Caches/firka-renew"
LOG="$HOME/Library/Logs/firka-renew.log"
export PATH=/usr/bin:/bin:/usr/sbin:/sbin

mkdir -p "$WORK"
log() { print -r -- "$(date '+%F %T') [$APP] $*" >> "$LOG" }
notify() { osascript -e "display notification \"$1\" with title \"$APP\"" >/dev/null 2>&1 || true }

# Profiles Xcode made for the app and its widget: "<file>\t<expiry epoch>" per line
profiles() {
  local f id exp
  for f in "$PROFILES"/*.mobileprovision(N); do
    security cms -D -i "$f" 2>/dev/null > "$WORK/p.plist" || continue
    id=$(plutil -extract Entitlements.application-identifier raw "$WORK/p.plist" 2>/dev/null) || continue
    [[ $id == "$TEAM.$APP_ID" || $id == "$TEAM.$APP_ID.widget" ]] || continue
    exp=$(plutil -extract ExpirationDate raw "$WORK/p.plist")
    print -r -- "$f"$'\t'"$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$exp" +%s)"
  done
}

# Earliest expiry of the two profiles (0 if there are none)
expiry() { profiles | cut -f2 | sort -n | head -1 | grep . || print 0 }

now=$(date +%s)
exp=$(expiry)
left=$(( exp - now ))
if [[ ${1:-} != --force ]] && (( left > RENEW_BEFORE )); then
  log "ok: $(( left / 3600 )) hours left, nothing to do"
  exit 0
fi

if ! xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -qE 'connected|available'; then
  log "iPhone not reachable ($(( left / 3600 )) hours left)"
  (( left < 24 * 3600 )) && notify "Nem éri el a telefont, a(z) $APP $(( left / 3600 )) óra múlva lejár. Legyen a telefon a Mac-kel egy Wi-Fi-n, feloldva."
  exit 1
fi

log "renewing ($(( left / 3600 )) hours left)"
if [[ $APP != Firka ]]; then
  # the other app's own install command (it requests fresh profiles itself)
  if DEVICE=$DEVICE eval "$OTHER_INSTALL" >> "$LOG" 2>&1; then
    log "done"; notify "$APP megújítva a telefonon, érvényes: $(LC_TIME=hu_HU.UTF-8 date -r "$(expiry)" '+%b %-d. %H:%M')"; exit 0
  fi
  log "failed"; notify "A(z) $APP megújítása nem sikerült. Részletek: ~/Library/Logs/firka-renew.log"; exit 1
fi
# Set the old profiles aside so Xcode has to request fresh 7-day ones; put them back if anything fails.
stash="$WORK/old-profiles"; rm -rf "$stash"; mkdir -p "$stash"
profiles | cut -f1 | while read -r f; do mv "$f" "$stash/"; done
restore() { mv "$stash"/*.mobileprovision(N) "$PROFILES/" 2>/dev/null; }

if ! xcodebuild -project "$PROJECT_DIR/Firka.xcodeproj" -scheme Firka -configuration Release \
     -destination "id=$DEVICE" -derivedDataPath "$WORK/build" -allowProvisioningUpdates build >> "$LOG" 2>&1; then
  restore
  log "build failed"
  notify "A Firka megújítása nem sikerült (fordítás). Részletek: ~/Library/Logs/firka-renew.log"
  exit 1
fi

if ! xcrun devicectl device install app --device "$DEVICE" "$WORK/build/Build/Products/Release-iphoneos/Firka.app" >> "$LOG" 2>&1; then
  log "install failed"
  notify "A Firka megújítása nem sikerült (telepítés). Legyen a telefon feloldva. Részletek: ~/Library/Logs/firka-renew.log"
  exit 1
fi

rm -rf "$stash"
until_date=$(LC_TIME=hu_HU.UTF-8 date -r "$(expiry)" '+%b %-d. %H:%M')
log "done, valid until $until_date"
notify "Firka megújítva a telefonon, érvényes: $until_date"
