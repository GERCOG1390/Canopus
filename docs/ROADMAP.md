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
5. **Space:** 3D map (as the desktop's), routes with avoidance, sovereignty, campaigns, jobs board.
6. **AI assistant** with the same tools as the desktop.
7. **Release:** bundle id and EVE SSO application for iOS, privacy manifest, App Store assets,
   TestFlight, App Store review.

Widgets and Live Activities (skill queue, industry jobs, radar) come with the phase their data
belongs to.

## Status

- 2026-10-27: Claude took the project over. The Mac working copy (older history and uncommitted
  work) is saved in the local branch `backup/mac-2026-09`; `main` follows GitHub. Phase 0 started.
- 2026-10-27: Phase 0 done (design system, shell, iPhone + iPad, Russian). Phase 1 in progress:
  character overview, skills, wallet redone; desktop fonts on every screen. Next: clones and
  implants, mail, character sheet, assets, contracts. Tools/l10n/sync_strings.py keeps the string
  catalogs in step; debug builds accept `-startPage <page>`.
- 2026-10-28: Phase 1 done: clones and implants, mail, assets redone; every list on the Canopus
  background with inline titles; cancelled requests no longer shown as errors. Character sheet, LP,
  orders, industry, mining and contracts have the desktop palette and fonts; their layouts get a
  deeper pass with the phases that extend them (economy). Next: phase 2, the fitting engine checked
  against Pyfa.
- 2026-10-28: the iOS SDE came from CCP's legacy S3 export (frozen since July 2025); the workflow and
  sde-import now use developers.eveonline.com. The old Swift dogma engine is gone: the app runs the
  desktop's engine in JavaScriptCore (Packages/EVEStaticData DogmaJS, Tools/dogma-js), 264/264 cases
  equal to Pyfa on the app's own SDE. Original icons only (desktop glyphs, CCP window/attribute icons).
  The fitting stats tab follows the desktop's panel (metrics, resources, firepower by weapon, defense
  table, capacitor, navigation, targeting) straight from the engine's result, with CCP attribute icons.
  Fit snapshot (the desktop's FitShot card, rendered to a picture for the share sheet); hardpoints,
  drone launch and cargo charges by the desktop's rules; the engine's fit problems shown in the panel
  and on module rows. Fitting tools tab: price optimizer and abyss planner as on the desktop, mission
  NPC damage — the desktop's npc.ts / abyss.ts / metrics.ts bundled unchanged (Tools/dogma-js/build.mjs
  points their SDE and index imports at shims); check_tools.py: 0 differences against the desktop's
  whole SDE. Also what to learn (the desktop's gains.ts), compare fits and popular fits (zKillboard
  losses, opened in the fitting screen): phase 2 done.
- 2026-10-28: the iOS database never had the map (sde-import had the tables but no import): it now
  imports regions, constellations, systems with coordinates and stargate links (`jumps`); the manifest
  carries `importer_version` so the workflow releases a new importer's data for the same CCP build. The
  app now prefers a newer bundled database over an older installed copy. 3D map v1 on Metal (the
  desktop's GalaxyMap): security colours, gates, kills in the last hour, region and system names,
  orbit / move / pinch, tap to pick, search, where am I, top / side / whole views, system card with
  kills and jumps, ESI routes (safest / shortest / low-null) with avoided systems and danger on the
  way, notes. Then sovereignty (alliance colours, raidable Skyhooks, timers), capital jump range
  (sphere and reachable systems by ship and JDC) and alliance jump bridges (pasted list, capital
  distances, routes over bridges worked out locally as the desktop's routeLocal). Still: intel marks
  (with phase 3), set destination in game (needs ui.write_waypoint with the new SSO app).
- 2026-10-28: phase 3 started. Intel page as the desktop's (Local check with threat rating from
  corp / alliance and zKillboard, groups filter, arrivals and departures; D-scan by class and type with
  notable groups; fleet composition; live kill radar on zKillboard's R2Z2 feed around the character's
  ESI location and the map's route, with gate camps, bubbles and smartbombs). Lists are pasted (Universal
  Clipboard from a Mac). The desktop's intel channels read the game's chat logs and stay desktop-only.
  PvP is now the desktop's pilot dossier (any pilot by name, zKillboard stats, recent fights with the
  victim's fit and the attackers); the old kill board screen is gone. Blue / red standings need the
  contacts scopes (esi-characters/corporations/alliances.read_contacts) with the new SSO app, as does
  "add dangerous pilots to contacts" (write_contacts). Radar notifications as the desktop's radarAlert
  (camps / bubbles / smartbombs, every kill, off; sound), banners while the app is open; notification
  permission asked when a notification is turned on, not at launch. Phase 3 done.
- 2026-10-28: item info as the desktop's InfoPanel (description with ship traits and links, attributes by
  category with units and icons, effects in words, requirement tree, skill, masteries, variations,
  industry, reprocessing, hub prices), in Russian from the SDE. sde-import 3: the new export's renamed
  keys were silently dropped (attribute display names, market group names); now read, plus units,
  attribute categories, meta groups, races, factions, blueprints, type materials, certificates,
  masteries and Russian texts (l10n, type_traits_ru, zlib-compressed type_descriptions_ru). Database
  43 MB (was 31). Item names elsewhere in the app stay English for now.
- 2026-10-28: names in the app's language everywhere (SDENames); EFT export stays English, EFT / fleet /
  search accept both. The fitting screen in the desktop's layout: ship card, DPS / EHP / CPU / PG
  metrics, slot groups with the game's icons and used / total, module rows (state button cycling as
  the desktop's nextState, identical modules as "6×", charge, problems, remove one), empty slots,
  drones with launched −/+ and ×+1, implants, cargo. Next: phase 4 (economy).

- 2026-10-30: phase 4, Market as the desktop's MarketPage: prices (market tree, search, an item's
  market: Jita / 30-day tiles, five hubs with spread, 90-day history, Jita 4-4 order books), loot
  appraisal, hub arbitrage (instant or with a sell order, tax / broker / min margin), LP store (own LP
  and popular corporations, ISK/LP after tax and hand-in items), my orders (outbid in red), my trades
  (FIFO profit, taxes and fees from the journal, unsold stock at Jita). Orders and LP pages now open
  Market's tabs. Next: industry.
- 2026-10-31: the market tree as the desktop's MarketTree (groups open in place with the game icon and
  item count, items Tech I → Tech II → faction… with the short meta badge and ⓘ), used by Market →
  Prices and by the reference, which is now search (Russian / English) plus that tree instead of the
  old SDE category lists with their odd item renders. sde-import 4: game UI icons resolved, as the
  desktop does, through the client's resfileindex to CCP's resource CDN (icons table, 3601 of 4806;
  the rest aren't in the client); third-party icon lookup only as a fallback for older databases.
