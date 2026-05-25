# Contributing

Thanks for your interest in contributing to Split Rewards.

Split Rewards is a Bitcoin wallet app. Changes can affect wallet custody, local secrets, wallet-authenticated sessions, messaging, payments, rewards, and released mobile clients. Please approach contributions with that context in mind.

## Public Repository Status

This public repository exists for transparency and source availability. Active development may happen privately before released code is synced here.

Pull requests may not be reviewed or merged quickly, and maintainers may prioritize private release work, production fixes, or mobile/backend compatibility work before public contributions.

## Start With An Issue Or Discussion

Small documentation fixes and typo corrections can be opened directly as pull requests.

For code changes, dependency updates, security-sensitive changes, API changes, wallet behavior, messaging behavior, release/build configuration, or larger documentation changes, please open an issue or discussion before starting implementation.

This helps avoid duplicated effort and lets maintainers confirm whether the change fits the current roadmap, security model, and mobile/backend compatibility requirements.

## Security Reports

Do not open public issues or pull requests for security vulnerabilities.

Use [SECURITY.md](./SECURITY.md) for responsible disclosure.

## Security-Sensitive Areas

Please be especially careful with changes involving:

- seed phrase creation, restore, display, deletion, and local storage
- Keychain storage and keychain access groups
- wallet authentication, signatures, nonces, and sessions
- Spark, Lightning, NWC, LND, Core Lightning, and Eclair wallet flows
- send, receive, payment review, and payment-status logic
- QR parsing, deep links, and payment request parsing
- messaging keys, encryption, attachments, sync, push routing, and sealed sender payloads
- legacy shared-storage cleanup and entitlement behavior
- backend API request/response shapes
- signing, entitlements, app groups, and bundle identifiers
- dependency updates and package resolution changes

## API And Backend Compatibility

Released mobile clients depend on backend API contracts.

Do not make breaking request or response changes in place. If a contract must change, propose a new version or new endpoint and keep the old path working until affected clients can be updated or forced to upgrade.

This applies especially to auth, profile, rewards, merchant reporting, messaging, wallet bootstrap, and version-gate routes.

## Development Setup

Open the project in Xcode:

```text
Split Rewards.xcodeproj
```

Public-safe build configuration lives in `Config/Debug.xcconfig` and `Config/Release.xcconfig`.

Private local overrides can be created from:

```text
Config/LocalDebug.xcconfig.example
Config/LocalRelease.xcconfig.example
```

Run tests with the normal Xcode test action for the project.

## Pull Request Expectations

Good pull requests should:

- be scoped to one issue or change
- describe the reason for the change
- call out wallet, messaging, and backend compatibility impact
- include tests where practical
- update docs when behavior, configuration, or security assumptions change
- explain dependency, lockfile, project-file, build, or generated configuration changes

Avoid unrelated refactors in the same pull request.

## Dependency Updates

Dependency updates are security-sensitive.

Before proposing them:

- inspect package/dependency resolution diffs
- avoid unnecessary major-version upgrades
- run the relevant tests
- explain why the update is needed
- call out any new transitive dependencies, repositories, plugins, lifecycle scripts, or build scripts if they appear unusual

## Secrets And Local Files

Never commit:

- wallet seeds or private keys
- NWC secrets, macaroons, runes, or API passwords
- production credentials
- database connection strings
- object storage credentials
- APNs/FCM/Firebase private keys
- signing keys, keystores, certificates, or provisioning profiles
- private support notes or incident details
- local-only config
- generated build artifacts

Use placeholders in examples and documentation.

## Documentation

Documentation changes should be accurate and conservative. Do not overstate privacy, anonymity, custody, or messaging-security guarantees.

For security assumptions and limits, refer to [THREAT_MODEL.md](./THREAT_MODEL.md).

## License

By contributing, you agree that your contribution will be licensed under this repository's Apache License 2.0.
