# Releasing the iOS app

A build goes to App Store Connect only through these steps. App Review takes days, so anything found
after upload costs a review cycle.

1. **Fix, commit, raise the build number** (`CURRENT_PROJECT_VERSION` in both targets; the version
   `MARKETING_VERSION` only for a new App Store version).
2. **`Tools/release/check.sh`** — the gate. It fails on any of:
   - package tests: the dogma engine against Pyfa's numbers, item lists → fits (saved fits, the live ship
     from assets, killmails), SDE queries;
   - the Release build for a device;
   - a visible string without Russian;
   - any screen (40 of them, iPhone and iPad) that crashes the app or leaves a crash report.
   Then look over `sheet-iphone.jpg` / `sheet-ipad.jpg` it prints: empty screens, errors, cut text.
3. **On a real iPhone** (`xcrun devicectl device install app …`), the things a simulator can't show:
   - sign in with EVE SSO and back to the app;
   - the current ship (Character → ship card) — a T3 cruiser if the pilot has one — slots match the game;
   - turn the phone and switch tabs with a fit open: the fit stays;
   - a notification arrives (allow notifications, reopen the app);
   - "Open in game" with the game client running.
4. **`Tools/release/upload.sh`** — archives and uploads, only for a commit the gate stamped; tags it
   `ios-<version>-<build>`.

Every bug found by hand gets a test first (Packages/EVEStaticData/Tests) or a screen in
`Tools/release/smoke.sh`, then the fix.
