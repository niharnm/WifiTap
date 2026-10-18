# Contributing to WifiTap

Thanks for helping. Bug reports, ideas, documentation fixes, and code are all welcome.

## Before you start

- For a bug, open an issue with the steps to reproduce it, your iPhone model and iOS version, the card type, and the card mode.
- For a larger change, open an issue first so we can agree on the approach before you write it.
- For a security problem, don't open an issue. Follow [SECURITY.md](SECURITY.md).

## Keep secrets out of the repository

WifiTap handles Wi-Fi passwords, so be strict about this:

- Never commit `ios/Config/Local.xcconfig`, `supabase/functions/.env`, signing certificates, provisioning profiles, or API keys. They are gitignored; keep them that way.
- Don't put real network names, passwords, card URLs, or tokens in code, tests, screenshots, issues, or pull requests. A card URL is enough to read that card's password. Use made-up values like `Guest` and `guest-password`.
- Never put the Supabase service role key or `TAG_ENC_KEY` in the iOS app. Only the Edge Functions use them.

## Development setup

Follow [Getting started](README.md#getting-started) in the README. For most app changes, the local test mode (no backend) is enough.

## Making changes

- **iOS:** edit `ios/project.yml`, not the generated `.xcodeproj`, then run `xcodegen generate`. The code targets Swift 6 with strict concurrency; keep it free of warnings.
- **Database:** add a new migration with `supabase migration new <name>`. Don't edit a migration that has already been released. Keep row level security enabled and grant columns explicitly, as the existing migration does.
- **Edge Functions:** never return or log a password, its ciphertext, or a full token. Log error codes and messages only.
- **Style:** match the surrounding code. Swift uses 4-space indentation; TypeScript and SQL use 2 spaces.
- **Scope:** keep each pull request focused on one change.

## Testing

Run the unit tests before opening a pull request:

```bash
cd ios
xcodegen generate
xcodebuild test -project WifiTap.xcodeproj -scheme WifiTap -destination 'platform=iOS Simulator,name=iPhone 17'
```

Add tests for new logic in `ios/Tests`. NFC writing and Wi-Fi joining need a real iPhone, so describe what you checked on a device in the pull request.

## Changes that need extra care

Explain the reasoning in the pull request when you touch any of these:

- encryption or token generation (`supabase/functions/_shared/crypto.ts`, `ios/Shared/CardLink.swift`)
- grants or row level security policies
- the rate limit or tap logging in `redeem-tag`
- the NDEF or Wi-Fi Simple Configuration encoding (`ios/App/CardMessage.swift`, `ios/Shared/WSCRecord.swift`)

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
