# Security Policy

Split Rewards is a Bitcoin wallet app. Please treat potential vulnerabilities with care and report them privately.

## Reporting A Vulnerability

Please do not open a public GitHub issue for security-sensitive reports.

Email security reports to:

```text
security@example.com
```

We aim to respond as soon as possible. If the report appears security-sensitive, we will keep the discussion private while we investigate and prepare a fix.

## What To Include

Helpful reports include:

- the affected repository, branch, commit, screen, flow, or file
- clear reproduction steps
- device model, iOS version, app build/version, and whether the device is jailbroken
- the expected and actual behavior
- the security impact, including whether funds, wallet identity, local secrets, messages, attachments, rewards, or profile data could be affected
- relevant logs, screenshots, crash traces, or proof-of-concept details
- whether the issue appears to affect a released app, a public snapshot, or only local development

Please keep proof-of-concept material minimal and non-destructive.

## Scope

Security-sensitive areas in the iOS app include:

- wallet seed phrase creation, restore, display, deletion, and local storage
- Keychain storage for wallet seeds, remote-node credentials, NWC secrets, messaging keys, and related local secrets
- wallet-authenticated backend login and signature flows
- Spark, Lightning, NWC, LND, Core Lightning, and Eclair wallet connection flows
- QR parsing, deep-link handling, and payment request parsing
- send, receive, payment review, and payment-status logic
- messaging encryption, key registration, sealed sender payloads, attachments, sync, and push routing
- legacy shared-storage cleanup and entitlement handling
- dependency vulnerabilities and supply-chain concerns
- configuration that could expose private infrastructure, signing material, or production secrets

## Out Of Scope

The following are generally out of scope unless they reveal a concrete security flaw in Split:

- spam, phishing, or social engineering reports
- physical device compromise outside Split's control
- attacks requiring an already-jailbroken device unless there is an app-specific failure
- malware, screen recording, keyboard logging, or clipboard access by another compromised app
- automated scanner output without verification or impact analysis
- disclosure of public placeholder configuration in this repository

## Testing Guidelines

Do not:

- move, spend, or attempt to move real funds
- attempt to obtain wallet seeds, private keys, NWC secrets, macaroon credentials, API passwords, or other local secrets from real users
- access, modify, delete, or exfiltrate data that does not belong to you
- run destructive tests against production infrastructure
- publicly disclose the issue before we have had a chance to investigate and remediate

Use your own wallet, device, account, and test funds when researching an issue.

## Supported Versions And Public Snapshots

This public repository exists for transparency and source availability. Active development and security fixes may land privately before public snapshots are refreshed.

Security fixes are prioritized for released app builds and the deployed backend first. Public repositories may be updated after the production fix and release path are complete.

## Bug Bounty

Split does not currently offer a paid bug bounty program.

We appreciate good-faith, responsible security reports.
