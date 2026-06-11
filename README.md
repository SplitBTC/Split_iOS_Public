# Split Rewards iOS

iOS client for Split.

This app includes:

- self-custodial Bitcoin wallet flows
- Lightning address management
- Split messaging
- rewards and merchant discovery flows

## Why This Project Exists

The project-purpose writeup lives here:

- [PROJECT_PURPOSE.md](./PROJECT_PURPOSE.md)

That document explains the core thesis behind Split: Bitcoin should be usable as money, spending requires coordination, and communication is part of making a real Bitcoin economy work.

## Repo Status

This repo is being prepared for public release.

It is a real iOS app project, not a sample app. Some infrastructure assumptions still point at Split-hosted services by default, so outside contributors should treat this as production code with public-repo hygiene requirements.

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
- adjust the bundle identifier if needed
- use your own signing configuration for device/archive builds

## Backend Configuration

Backend URLs are provided through xcconfig files, not hardcoded directly in Swift.

Committed public-safe defaults live in:

- [Config/Debug.xcconfig](./Config/Debug.xcconfig)
- [Config/Release.xcconfig](./Config/Release.xcconfig)

Private local overrides can be created from:

- [Config/LocalDebug.xcconfig.example](./Config/LocalDebug.xcconfig.example)
- [Config/LocalRelease.xcconfig.example](./Config/LocalRelease.xcconfig.example)

Those local override files are gitignored.

Set backend config with:

- `BASE_SCHEME`
- `BASE_HOST`

The app reads the configured base URL in [AppConfig.swift](./Split%20Rewards/Utilities/AppConfig.swift).

If you are not an authorized developer working against Split infrastructure, point the app at your own backend before using it as a development client.

## Project Highlights

- [Split_RewardsApp.swift](./Split%20Rewards/Split_RewardsApp.swift): app entry point
- [Utilities/AppConfig.swift](./Split%20Rewards/Utilities/AppConfig.swift): backend base URL selection
- [Message Manager](./Split%20Rewards/Message%20Manager): messaging key management, crypto, sync, and storage
- [Wallet SDK Manager ](./Split%20Rewards/Wallet%20SDK%20Manager%20): wallet lifecycle and seed handling
- [Views](./Split%20Rewards/Views): app screens and sheets

## Testing

This repo includes:

- unit test target: [Split RewardsTests](./Split%20RewardsTests)
- UI test target: [Split RewardsUITests](./Split%20RewardsUITests)

Run tests from Xcode using the normal test action for the project.

## Messaging Notes

The messaging trust/privacy writeup lives here:

- [MESSAGING_PRIVACY_AND_TRUST.md](./MESSAGING_PRIVACY_AND_TRUST.md)
- [IOS_MESSAGING_V4_BUILD_PLAN.md](./IOS_MESSAGING_V4_BUILD_PLAN.md)

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
