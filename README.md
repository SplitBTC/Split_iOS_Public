# Split Rewards iOS

iOS client for Split.

This app includes:

- self-custodial Bitcoin wallet flows
- Lightning address management
- Split messaging
- rewards, coupons, merchant discovery, and Bitcoin event flows
- external Lightning node and Nostr Wallet Connect flows

## Why This Project Exists

The project-purpose writeup lives here:

- [PROJECT_PURPOSE.md](./PROJECT_PURPOSE.md)

That document explains the core thesis behind Split: Bitcoin should be usable as money, spending requires coordination, and communication is part of making a real Bitcoin economy work.

## Repo Status

This is a real iOS app project, not a sample app.

This public repository exists for transparency and source availability. Active development may occur privately before released code is synced here. Pull requests may not be reviewed or merged.

Outside developers should treat this as production code with public-repo hygiene requirements.

## Requirements

- Xcode 17 or newer recommended
- Swift 5
- iOS deployment target: `17.6`
- Apple Developer account if you want to run on device or archive

## Opening the Project

Open:

- [Split Rewards.xcodeproj](./Split%20Rewards.xcodeproj)

The main app sources live in:

- [Split Rewards](./Split%20Rewards)

Test targets live in:

- [Split RewardsTests](./Split%20RewardsTests)
- [Split RewardsUITests](./Split%20RewardsUITests)

## Build Notes

The app uses automatic signing in the project file. If you are building under your own Apple account, you will probably need to:

- set your own development team
- adjust the bundle identifiers if needed
- replace the placeholder shared app-group and shared keychain identifiers
- use your own signing configuration for device/archive builds

This public snapshot includes the main app and the test targets.

## Backend Configuration

Backend URLs are provided through xcconfig files, not hardcoded directly in Swift.

Committed public-safe defaults live in:

- [Config/Debug.xcconfig](./Config/Debug.xcconfig)
- [Config/Release.xcconfig](./Config/Release.xcconfig)

Private local overrides can be created from:

- [Config/LocalDebug.xcconfig.example](./Config/LocalDebug.xcconfig.example)
- [Config/LocalRelease.xcconfig.example](./Config/LocalRelease.xcconfig.example)

Those local override files are gitignored.

Set backend and messaging config with:

- `BASE_SCHEME`
- `BASE_HOST`
- `MESSAGING_PUSH_ENV`
- `MESSAGING_IDENTITY_DOMAIN`
- `LIGHTNING_ADDRESS_DOMAIN`

The main app reads these values in [AppConfig.swift](./Split%20Rewards/Utilities/AppConfig.swift).

The public project also uses placeholder values for:

- shared app-group identifier
- shared keychain access group
- keychain service namespace
- messaging identity domain
- Lightning address domain
- public support/contact examples

Those values are intentionally public-safe in this repository and should be replaced with your own app identifiers for real signed builds.

If you are not an authorized developer working against Split infrastructure, point the app at your own backend before using it as a development client.

## Project Highlights

- [Split_RewardsApp.swift](./Split%20Rewards/Split_RewardsApp.swift): app entry point
- [Utilities/AppConfig.swift](./Split%20Rewards/Utilities/AppConfig.swift): backend base URL selection
- [Message Manager](./Split%20Rewards/Message%20Manager): messaging key management, crypto, sync, and storage
- [Wallet SDK Manager ](./Split%20Rewards/Wallet%20SDK%20Manager%20): wallet lifecycle and seed handling
- [NWC Wallet Manager](./Split%20Rewards/NWC%20Wallet%20Manager): Nostr Wallet Connect support
- [LND Wallet Manager](./Split%20Rewards/LND%20Wallet%20Manager): remote LND node support
- [Core Lightning Wallet Manager](./Split%20Rewards/Core%20Lightning%20Wallet%20Manager): remote Core Lightning node support
- [Eclair Wallet Manager](./Split%20Rewards/Eclair%20Wallet%20Manager): remote Eclair node support
- [Spark Subwallet Manager](./Split%20Rewards/Spark%20Subwallet%20Manager): Spark subwallet support
- [Views](./Split%20Rewards/Views): app screens and sheets

## Testing

This repo includes:

- unit test target: [Split RewardsTests](./Split%20RewardsTests)
- UI test target: [Split RewardsUITests](./Split%20RewardsUITests)

Run tests from Xcode using the normal test action for the project.

## Messaging Notes

The messaging trust/privacy writeup lives here:

- [MESSAGING_PRIVACY_AND_TRUST.md](./MESSAGING_PRIVACY_AND_TRUST.md)

That document is intentionally technical and conservative in scope.

## Open Source Hygiene

Before publishing or contributing, treat this repo as public:

- do not commit wallet seeds
- do not commit local signing assets
- do not commit provisioning profiles
- do not commit private support material
- do not assume the default backend URLs are appropriate for your own fork

## License

This repository is licensed under the Apache License 2.0.

See [LICENSE](./LICENSE).
