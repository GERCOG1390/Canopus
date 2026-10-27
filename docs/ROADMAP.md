# Canopus iOS — roadmap

Goal: the mobile Canopus in the style of, and on the basis of, the desktop app
([canopus-desktop](https://github.com/GERCOG1390/canopus-desktop)). Native SwiftUI, iPhone + iPad,
TestFlight first, then the App Store.

## Principles

- **One product.** The same design tokens, fonts, section names and wording as the desktop
  (`src/renderer/src/styles.css`, `src/renderer/src/i18n/dict.ts`). Russian and English.
- **Same numbers as the desktop.** The Swift dogma engine is checked against Pyfa with the same
  differential test the desktop passes (44 fits, normal space and abyssal weather, 0 differences).
- **Only what CCP allows.** ESI with the pilot's consent, the SDE, zKillboard. Nothing that reads or
  drives the game client.
- iPhone: tab bar by the desktop's sections. iPad: the desktop's sidebar (NavigationSplitView).

## Phases

0. **Foundation**
   - design system: desktop colors, IBM Plex Sans / Exo 2 / IBM Plex Mono, cut-corner cards, stat
     tiles, section headers, tabs, buttons; accent themes;
   - navigation shell: Pilot · Combat · Economy · Space · Settings;
   - iPhone + iPad only (macOS and visionOS removed: the desktop covers the Mac);
   - RU / EN.
1. **Pilot:** character overview, all characters, skills and queue, what to learn, implants and
   clones, mail, wallet, assets, contracts, notifications.
2. **Fitting:** engine parity with Pyfa, the fitting screen, stats, fit snapshot, saved and in-game
   fits, price optimizer, NPC and abyss planner.
3. **Combat and intel:** pilot lookup (zKillboard), Local / d-scan paste, kill radar (route and
   nearby), route safety, combat simulator.
4. **Economy:** market with Jita / hub prices, my trades, industry jobs and blueprints, mining
   ledger, LP store.
5. **Space:** map (2D on the phone), routes with avoidance, sovereignty, campaigns, jobs board.
6. **AI assistant** with the same tools as the desktop.
7. **Release:** bundle id and EVE SSO application for iOS, privacy manifest, App Store assets,
   TestFlight, App Store review.

Widgets and Live Activities (skill queue, industry jobs, radar) come with the phase their data
belongs to.

## Status

- 2026-10-27: Claude took the project over. The Mac working copy (older history and uncommitted
  work) is saved in the local branch `backup/mac-2026-09`; `main` follows GitHub. Phase 0 started.
