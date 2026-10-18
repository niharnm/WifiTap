# Phase 1 Device Test Matrix

Phase 1 answers one question before any further build: can a guest tap a card and join Wi-Fi on iPhone (App Clip) and Android (no app)?

Fill in Result with Pass, Fail or Blocked, plus the iOS or Android version and anything iOS or Android showed on screen.

## Go / no-go

- **Go:** I1, I4 and A1 pass. The App Clip signs with the Hotspot Configuration entitlement, a card tap launches it, iOS shows its join prompt, and the same combined card shows Android's Connect prompt.
- **No-go, iPhone:** I1 or I4 fails because the entitlement or `apply` is rejected inside an App Clip. Stop and rethink the iPhone flow before building more.
- **No-go, combined card:** I4 passes with a link-only card but fails with a combined card, or A1 fails on both test phones. Fall back to link-only cards.

## Setup

1. Copy `ios/Config/Local.xcconfig.example` to `ios/Config/Local.xcconfig`. Set your team, bundle prefix, domain, and a **guest** test network.
2. `cd ios && xcodegen generate && open WifiTap.xcodeproj`
3. On the iPhone: turn on Developer Mode. Run the **WifiTap** scheme once, then run the **WifiTapClip** scheme so the App Clip is installed.
4. On the iPhone: Settings > Developer > App Clips Testing > Local Experiences > Register Local Experience.
   - URL prefix: `https://<TAG_DOMAIN>/t/`
   - Bundle ID: `<BUNDLE_ID_PREFIX>.WifiTap.Clip`
   - Title and subtitle: anything. Action: Open.
5. Use NTAG215 or NTAG216 cards.

In Phase 1a the App Clip joins the network from `Local.xcconfig`, whatever token is on the card. Phase 1b swaps that for the server lookup.

## iPhone

| ID | Test | Expected | Result |
| --- | --- | --- | --- |
| I1 | Run WifiTapClip on the iPhone with automatic signing | Signs with Hotspot Configuration and launches | |
| I2 | In WifiTap, write an "iPhone + Android" card | "Card ready... verified" with byte count | |
| I3 | Write a 32-character SSID and 63-character password to an NTAG213 | Clear "card holds N bytes" error, nothing written | |
| I4 | Delete the full WifiTap app. Unlocked iPhone, tap the combined card | Banner, App Clip card, Open, iOS "Join network?" prompt, joins | |
| I5 | Same as I4 with a "Link only" card | Same as I4 | |
| I6 | Tap with the iPhone locked | iOS asks for Face ID or the passcode first, then continues as I4 | |
| I7 | Tap while already on the test network | "Already on <network>" | |
| I8 | Tap and choose Cancel on the iOS prompt | "Didn't join <network>" | |
| I9 | Set a wrong password in Local.xcconfig, rebuild, tap | Record what iOS shows. Apple notes `apply` may not report a failed join | |
| I10 | WPA3-only test network | Record whether iOS joins | |
| I11 | After I4, open Settings > Wi-Fi | Network is saved (`joinOnce` is off) | |
| I12 | After I11, delete the App Clip (Settings > App Clips) and check Settings > Wi-Fi | Record whether the saved network is removed with the App Clip | |
| I13 | Camera app open, then tap the card | Background reading is unavailable while the camera is in use; record behavior | |

## Android (no app installed)

| ID | Test | Expected | Result |
| --- | --- | --- | --- |
| A1 | Pixel, unlocked, tap the combined card | System "Connect to network" prompt, joins | |
| A2 | Samsung, unlocked, tap the combined card | Same as A1 | |
| A3 | Tap with the screen locked | Phone must be unlocked first; record behavior | |
| A4 | Open network card | Joins with no password | |
| A5 | WPA3-only test network | Record result. Android's NFC parser maps the card to WPA2-Personal, so a WPA3-only network may fail | |
| A6 | Tap a "Link only" card | Opens `https://<TAG_DOMAIN>/t/<token>` in the browser (fallback page once `web/` is deployed) | |

## Phase 1b (backend)

| ID | Test | Expected | Result |
| --- | --- | --- | --- |
| B1 | With `SUPABASE_URL` set, write a card | Card URL token matches the `create-tag` response | |
| B2 | Tap that card on iPhone | App Clip fetches credentials and shows the join prompt | |
| B3 | Set the tag's `status` to `revoked`, tap again | "Card unavailable: This card was turned off by its owner." | |
| B4 | Set `expires_at` in the past, tap again | "This card has expired." | |
| B5 | TestFlight build, real domain with AASA deployed, tap card | App Clip opens without a Local Experience | |

## Results log

| Date | Tester | Devices and OS versions | Notes |
| --- | --- | --- | --- |
| | | | |
