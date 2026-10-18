# Security policy

WifiTap stores and serves Wi-Fi passwords, so security reports are taken seriously.

## Reporting a vulnerability

Please report vulnerabilities privately through GitHub: open the repository's **Security** tab and choose **Report a vulnerability**. Don't open a public issue, pull request, or discussion for a security problem.

Include what you found, how to reproduce it, and what an attacker could do with it. Don't include real Wi-Fi passwords, card URLs, or keys. If you need to show a working example, use a test network and a card you created.

Reports are handled on a best-effort basis by the maintainer. Fixes are made on `main`, and the advisory is published once a fix is available.

## Supported versions

WifiTap is pre-1.0. Only the latest commit on `main` receives security fixes.

## Scope

In scope:

- A client reading a stored password or its ciphertext without redeeming a valid card token
- Bypassing row level security or column grants to read or change another owner's cards or tap log
- Guessing or enumerating card tokens, or bypassing the `redeem-tag` rate limit
- Weaknesses in how passwords are encrypted, or in how tokens are generated
- The App Clip or app joining a network the card did not point to

Out of scope, because they are documented behavior:

- Reading the password from a card written in iPhone + Android (`url_and_wifi`) mode. The Wi-Fi record on the card holds it in plain text so Android can join without an app.
- Redeeming a card with its URL. The card token is the credential, the same as tapping the card.
- Revocation and expiry not applying to Android taps on `url_and_wifi` cards, since those taps never reach the server.

## Running your own deployment safely

- Generate `TAG_ENC_KEY` with `openssl rand -base64 32` and store it only as a Supabase function secret.
- Keep the Supabase service role key on the server. The iOS app needs only the publishable (anon) key.
- Put cards on a guest network, and prefer Link only (`url_only`) mode when you need to revoke cards.
- Keep `ios/Config/Local.xcconfig` and `supabase/functions/.env` out of version control.
