# Firka for iOS

SwiftUI rewrite of Firka (KRÉTA client). README.md has the layout, install and release steps.

## Test-driven (the owner's rule)

Every change starts with a test, so anything that breaks shows up as a failing test:
1. Write the test first and run it: it must fail, for the reason you expect.
2. Write the least code that makes it pass; then tidy with the tests green.
3. A bug is fixed only after a test reproduces it (fails before the fix, passes after).
4. Logic goes in functions without UI (e.g. `TimetableNav`, `Notifier.changes`, `Ora.keep`) so it can be tested; views only call them.
5. `scripts/test.sh` green before every commit and every install on the phone (`FAST=1` for unit tests only while iterating).
6. Network code is tested against `FirkaTests/Stub.swift` (fake KRÉTA); tests touching the keychain, cache file or UserDefaults go in the serialized `Global` suite.
7. Screens get a UI test in `FirkaUITests/` (demo mode, `FIRKA_DEMO=1`); give tapped elements an `accessibilityIdentifier`.
8. Light and dark mode both: `testContrastInLightAndDarkMode` audits the main screens' contrast in each; own colour pairs (grade badges, absence states, the Live Activity, which UI tests can't reach) go in `FirkaTests/ColorTests.swift`.

Run one suite: `xcodebuild test -scheme Firka -destination 'platform=iOS Simulator,name=<sim>' -only-testing:FirkaTests/<Suite>`

## Working here

- UI text is Hungarian; code, comments and commit messages are English.
- Commits use the owner's own git identity, with no Claude co-author or attribution lines.
- Personal settings stay out of git: `Config/Local.xcconfig` (APP_ID, DEVELOPMENT_TEAM), `scripts/renew.local.sh` (iPhone id).
- Install on the owner's iPhone: `scripts/renew-on-iphone.sh --force`; the build number in Beállítások › Névjegy shows which build is on it.
- The remote is the owner's fork (`origin`, branch `ios`); never open pull requests against QwIT-Development/firka.
