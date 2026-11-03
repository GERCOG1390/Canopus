# Canopus — Privacy Policy

*Last updated: November 3, 2026*

Canopus is a companion app for the game EVE Online, made by an independent developer (Oleksandr Deriugin). This policy explains what happens to your data when you use the app on iPhone or iPad.

## The short version

Canopus does not collect, store or sell any of your data. There are no accounts with the developer, no analytics, no advertising and no tracking. Everything the app shows is fetched directly from the services listed below and kept only on your device.

## Signing in with EVE Online

You can sign in with your EVE Online character through CCP's official login (EVE SSO). Canopus never sees your EVE password: the sign-in happens on CCP's website, and the app receives an access token for the permissions you approve. The tokens are stored in the iOS Keychain on your device and are used only to request your character's data from CCP's ESI API. Removing a character in Settings deletes its tokens; uninstalling the app removes everything.

## Where the app's data comes from

The app talks directly to these services; the developer runs no server in between:

- **CCP Games — EVE Swagger Interface (esi.evetech.net)** and **EVE SSO (login.eveonline.com)**: your character's skills, wallet, assets, fits, mail and other game data, and public game data.
- **CCP image server (images.evetech.net)** and **resources.eveonline.com**: portraits, logos and item icons.
- **zKillboard (zkillboard.com)**: public kill and loss records.
- **EVE-Scout (eve-scout.com)**: public Thera and Turnur wormhole connections.
- **Fuzzwork Market (market.fuzzwork.co.uk)**: public market prices.
- **GitHub (github.com)**: updates of the app's static game database.

These requests include only what each service needs (for example, a character ID or an item ID), plus the app's name in the User-Agent header. Each service has its own privacy policy.

## On your device

Canopus keeps on your device: the sign-in tokens (Keychain), your settings, watchlists, fit drafts and a cache of game data. Notifications (skill training, industry jobs, planetary extractors, structure timers) are scheduled locally by the app; nothing is sent to a push server. Fit snapshots are saved to your photo library only when you choose to save one.

## Children

Canopus is not directed at children under 13 and collects no personal information from anyone.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions about this policy: gercogunlimited@gmail.com

---

EVE Online and all related logos and images are trademarks or registered trademarks of CCP hf. Canopus is a third-party application and is not affiliated with or endorsed by CCP hf.
