# Split Rewards Public AGENTS.md

## Optional Internal Context

- Internal Split agents with access to the full project folder may also review `PROJECT_MAP_INTERNAL.md` at the project root for cross-repo context.
- External or public-only review agents should ignore that file. This repo's `AGENTS.md` is the complete repo-local guidance.

## Repo Role

This is the public iOS repository for Split.

- It exists for inspection, transparency, and community scrutiny.
- It is not the primary day-to-day development repo.
- It may intentionally lag behind the private `Split Rewards` repo.
- It should represent a public-safe snapshot of the production iOS app when the user chooses to sync it.

## Intended Consumers

This file is for both implementation agents and review agents.

- Use it to understand what this repo is for before proposing changes or filing review findings.
- Do not treat this repo like the private source-of-truth iOS repo unless explicitly instructed.

## System Relationships

- Private iOS development happens in `Split Rewards`.
- This repo is a public publication target for iOS code that is ready to be exposed.
- `Split Backend Public` plays the same role for the backend.
- A public Android repo is planned later and should follow the same publication model.

## Non-Negotiable Rules

- This repo must always be open-source ready.
- Do not assume this repo should always mirror the private iOS repo.
- Only sync code here when the user wants the public repo updated to a production-ready snapshot.
- Treat every push to `main` as an immediate public release.
- There is no dev branch safety net here. If a change is not ready for public exposure, it does not belong in this repo.
- This repo is not primarily for outside contributions. Its main purpose is transparency, inspection, and scrutiny.
- Never launch iOS simulators from this machine. The user tests manually on physical devices.

## Review Posture

If you are reviewing this repo:

- Judge it as a public publication target, not as the main active development repo.
- Do not assume that a difference from the private iOS repo is automatically a bug.
- Do flag anything that weakens public transparency, public safety, or the coherence of the published snapshot.
- Prioritize findings around secrets, signing material, internal-only docs, misleading README/config guidance, or a snapshot that is obviously incomplete or inconsistent.
- Treat "this repo is behind private development" as expected unless the user says the public mirror should already include newer work.

## Public Release Rules

- Before publishing here, check for wallet seeds, signing assets, provisioning material, private support docs, internal notes, and local-only config.
- Keep backend configuration public-safe through xcconfig defaults and example local overrides.
- Keep bundle identifiers, app-group identifiers, keychain access groups, messaging/lightning placeholder domains, support/contact examples, and development-team settings public-safe unless the user explicitly chooses otherwise.
- Make sure README and public docs accurately describe the repo’s public role and limitations.
- If private repo features are incomplete, experimental, or not ready for public scrutiny, leave them out until the user decides to sync them.

## Private-To-Public Sync Workflow

- Treat the private `Split Rewards` repo as the implementation source and this repo as a sanitized publication mirror.
- Do not do a blind file-for-file mirror from private to public.
- Sync newer production-ready app code and tests from private only after a publication sweep.
- Preserve the public repo's sanitization layer when it already exists.

When updating this public repo from private:

- keep public-facing README, AGENTS, and publication-oriented docs as the base versions
- update those docs only as needed to reflect new code or changed behavior
- preserve public-safe placeholders for bundle identifiers, app-group identifiers, keychain access groups, messaging/lightning domains, support/contact examples, development team settings, and related config
- keep stricter public ignore rules and local-override patterns in place
- exclude local-only config files, machine-specific Xcode state, signing material, provisioning assets, and internal-only notes

Default review stance during a sync:

- implementation changes should usually come from private
- sanitization, placeholder config, entitlements strategy, and public positioning should usually stay from public
- if the private version would reintroduce real identifiers or internal setup, re-apply the public version or adapt the change before publishing

## Current Repo Shape

- `Split Rewards.xcodeproj`: Xcode project
- `Split Rewards/`: main app sources
- `Split RewardsTests/`: unit tests
- `Split RewardsUITests/`: UI tests
- `Config/`: public-safe backend configuration and local override examples
- `Split-Rewards-Info.plist`: app Info plist

Current public snapshot notes:

- This public repo currently exposes the main app and the test targets.
- Public-safe placeholder bundle identifiers and shared app-group/keychain identifiers are expected here; production identifiers should not be published.
- Trust the actual public repo contents when describing what is publicly available.

## Working Rules For Future Changes

- If syncing from `Split Rewards`, do a publication sweep before pushing:
- remove or avoid private signing material
- remove internal-only material
- verify local-only config is not committed
- verify docs reflect the public snapshot accurately
- verify the public code is coherent and production-ready
- preserve the public repo's sanitized README/docs/config/entitlements posture unless the user explicitly wants that changed
- Keep backend URLs configurable through `Config/` and `Utilities/AppConfig.swift`.
- Preserve the same backend contract discipline as the private app: public code should reflect stable, production-safe API usage.
- If a feature is live privately but not intended for public release yet, do not assume it belongs here.
- If asked to review or update this repo, optimize for public clarity and publication readiness, not internal development speed.

## Testing And Verification

- Never run iOS simulators on this machine.
- The user tests manually on physical devices.
- Safe verification includes static review, project inspection, targeted builds, and public-safety sweeps.

## Coordination Notes

- Active feature work usually starts in the private `Split Rewards` repo.
- This repo should be updated when the user decides the public iOS snapshot should move forward.
- Never treat this repo like a staging branch.
- If unsure whether something is public-safe, stop and confirm before publishing.
