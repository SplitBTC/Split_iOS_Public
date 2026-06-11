# Split Rewards AGENTS.md

## Optional Internal Context

- Internal Split agents with access to the full project folder should also review `PROJECT_MAP_INTERNAL.md` at the project root for cross-repo context.
- That file is supplemental only. This repo's `AGENTS.md` must remain sufficient on its own.

## Repo Role

This is the primary live mobile client for Split.

- It is the production iOS app currently live in the App Store.
- New feature work should usually begin here first.
- It is the product and behavior reference for `Split Android` unless the user explicitly says otherwise.

## System Relationships

- `Split Rewards` is served by the `Split` backend.
- Backend API changes must preserve compatibility for released iOS builds.
- `Split Android` should follow this repo for product behavior and backend contract usage after iOS changes are stable.

## Non-Negotiable Rules

- Never assume the backend can take a breaking change in place. Coordinate versioned backend endpoints when contracts need to change.
- Treat this repo as the lead client for new feature development.
- Keep backend URL configuration in xcconfig files and `Utilities/AppConfig.swift`; do not hardcode environment URLs in random Swift files.
- Never launch iOS simulators from this machine. The user tests manually on physical devices. Building, static review, and non-simulator verification are fine.
- Do not commit wallet seeds, private signing material, provisioning assets, or local-only config.
- File headers and generated page headers must never say `Created by Codex`; always use `Created by TeeVee`.

## Current Status

- This is the main live frontend in production now.
- It is the first place new development should happen.
- The user is comfortable working with Swift and Node.js.

## Current Repo Shape

- `Split_RewardsApp.swift`: app entry, version gate, root environment objects
- `MainTemplateView.swift`: top-level tab shell and live messaging sync loop
- `Utilities/`: app config, auth/session logic, app state, keychain helpers, shared utilities
- `Wallet SDK Manager /`: wallet lifecycle, auth signing support, payments, contacts, deposits, transaction handling
- `Message Manager/`: messaging key registration, sync, crypto, storage, push token sync, routing
- `Functions/`: focused backend calls for rewards, profile, feed, on-ramp, merchant reporting, Breez API key, etc.
- `Views/`: components, screens, and sheets
- `Config/`: xcconfig-based environment configuration

## Build And Dependency Notes

- Xcode project: `Split Rewards.xcodeproj`
- Deployment target is iOS 17.6 in repo docs
- Swift package dependencies currently include Breez Spark, Bip39, secp256k1, and JWTDecode

## Backend Contract Surface Used Here

Important current calls include:

- version gate: `/rewards-version-check`
- auth/session: `/auth/nonce`, `/auth/wallet-login`, `/session`
- Breez bootstrap: `/breez-api-key`
- profile media: `/Profile_Pic`, `/Upload_Profile_Pic`
- rewards and on-ramp: `/v1/RewardStats`, `/BuyRamp`, `/reward_onRamp_buy`, `/moonpay/prepare-buy`
- merchant reporting: `/ReportMerchantPubkey`
- messaging: `/messaging/v4/*` for identity, lookup, send, inbox, ack, outgoing statuses, device registrations, blocks, and attachments

## Environment Configuration

- Public-safe defaults live in `Config/Debug.xcconfig` and `Config/Release.xcconfig`
- Local overrides are expected through local xcconfig files
- `Utilities/AppConfig.swift` constructs the base URL from configured scheme/host values

When working on config-related tasks:

- start in `Config/`
- then verify how `AppConfig.swift` consumes the values
- avoid baking environment assumptions directly into feature code

## Working Rules For Future Changes

- Implement new product work here first unless told otherwise.
- If a feature needs backend changes, coordinate them with `Split` using version-safe API evolution.
- If a feature affects Android eventually, keep the user-visible behavior and backend contract cleanly portable.
- If a task touches wallet/auth flows, start with `Wallet SDK Manager /` and `Utilities/AuthManager.swift`.
- If a task touches messaging, start with `Message Manager/` and `MainTemplateView.swift`.
- If a task touches navigation or product presentation, inspect `MainTemplateView.swift`, `Views/Screens/`, and `Views/Sheets/`.

## Testing And Verification

- Do not run an iOS simulator on this machine.
- The user tests manually on real devices.
- Safe verification paths include code review, targeted builds, project inspection, and non-simulator checks.
- Unit/UI test targets exist, but do not use simulator-driven workflows unless the user explicitly changes this rule.

## Coordination Notes

- This repo leads feature development.
- `Split Android` is intentionally downstream of iOS right now.
- Once an iOS feature is production ready, the next step is usually to mirror it into Android with backend compatibility preserved.
