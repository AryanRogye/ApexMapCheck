# Apex Map Check Agent Handbook

This repository is maintained primarily by coding agents. Treat this file as the operating contract for every change: understand the product, make complete decisions, preserve its identity, validate the result, and leave the repository in a state another agent can safely continue from.

## Product Contract

Apex Map Check is a dark, fast-glance companion for Apex Legends players. Its core promise is simple: before a player queues, they can quickly see the live map, the next map, and when the rotation changes. The app also surfaces legend pick rates, official patch-note links, and home/Lock Screen widgets.

Every change must preserve these priorities, in order:

1. Current rotation information is correct and easy to scan.
2. Cached information remains useful when the network or provider fails.
3. The app and widgets agree about shared rotation state.
4. The interface feels intentionally made for Apex, not like a generic dashboard.
5. Accessibility, adaptive layout, and failure states are part of the feature.

Do not invent provider data, silently show stale data as fresh, or sacrifice legibility for decoration. Keep the existing disclaimer that the app is not affiliated with EA or Respawn, and retain data-provider attribution where provider data is displayed.

## Agent Ownership and Decision Making

Agents are expected to carry work from investigation through verification without relying on the user to perform routine engineering steps.

- Inspect the relevant implementation, repository status, and recent conventions before editing.
- Make reasonable, reversible assumptions when details are underspecified. Record important assumptions in the final handoff.
- Ask the user only when a decision changes product meaning, requires credentials or external authority, is destructive, or has multiple materially different outcomes that cannot be inferred from the repository.
- Implement the complete vertical slice. Do not leave placeholder UI, fake success paths, commented-out code, orphaned files, or `TODO` markers in place of requested behavior.
- Preserve unrelated user changes in a dirty worktree. Never reset, discard, rewrite, or stage work outside the requested scope.
- Keep changes focused, but fix directly related correctness, accessibility, or state-handling defects discovered along the way when the fix is low-risk.
- Do not claim a build, test, preview, or runtime check passed unless it was actually run. State exact limitations when an environment prevents verification.
- Update this handbook when a change establishes a new lasting directory, architecture, build, design-system, or validation convention.

## Repository Map and File Placement

The Xcode project uses file-system-synchronized groups. Files placed inside `ApexMapCheck/`, `ApexMapCheckWidgets/`, or `Shared/` are normally discovered automatically by their corresponding targets. Do not edit `project.pbxproj` merely to add a Swift file in one of those existing synchronized directories.

### Existing top-level areas

| Path | Ownership and allowed contents |
| --- | --- |
| `ApexMapCheck/` | Main iPhone app: SwiftUI screens, app-only view models, app-only services, Keychain access, app assets, entitlements, and configuration. |
| `ApexMapCheckWidgets/` | WidgetKit extension: timeline provider, widget views, widget App Intents, widget assets, previews, and extension configuration. |
| `Shared/` | Code compiled into **both** targets: rotation models, provider access needed by both targets, app-group cache/state, and shared projection logic. It must not import or reference app-only types. |
| `ApexMapCheck.icon/` | Icon Composer source. Preserve it as the source of truth for the application icon. |
| `ApexMapCheck.xcodeproj/` | Targets, schemes, build settings, synchronized groups, and Xcode Cloud metadata. Change only when target/build configuration truly changes. |
| `.githooks/` | Repository compatibility hooks. Keep them portable POSIX shell scripts. |
| `Secrets.example.plist` | Key-name/template documentation only; never place a real credential here. |

### Placement for new code

The current app is small and some source files remain flat. Do not perform a broad file move only to make the tree look cleaner. As features grow, use these destinations:

- `ApexMapCheck/Features/<Feature>/`: a feature's screen, components, and app-only view model.
- `ApexMapCheck/DesignSystem/`: reusable Apex-specific visual primitives and tokens used by multiple app screens.
- `ApexMapCheck/Services/`: app-only remote-data or parsing services.
- `ApexMapCheck/Storage/`: app-only persistence, Keychain, or configuration stores.
- `ApexMapCheckWidgets/`: all widget-only UI, intent, and timeline behavior; split by widget feature when needed.
- `Shared/`: only types or behavior genuinely required by both the app and extension.
- `ApexMapCheck/Assets.xcassets` and `ApexMapCheckWidgets/Assets.xcassets`: target-specific colors and images.
- `ApexMapCheckTests/` and `ApexMapCheckWidgetsTests/`: future XCTest targets, mirroring production names and feature structure.

When adding a file to `Shared/`, compile the full scheme immediately: it must remain valid in both target contexts. Avoid putting app navigation, Keychain APIs, app-only assets, or main-target-only services there.

## Current Architecture and Data Flow

Follow the existing dependency direction:

```text
SwiftUI view
    -> @MainActor observable view model
        -> actor/Sendable service or store
            -> remote provider and local cache

Widget view
    <- timeline entry
        <- RotationProvider
            -> Shared/RotationStore
                -> app-group snapshot / RotationAPI
```

Important contracts:

- `ContentView` owns primary navigation and a single `RotationViewModel` shared by rotation, intel, and settings flows.
- The app is iPhone-only and uses a tab bar for primary navigation. Keep layouts adaptive across supported iPhone sizes and orientations.
- `RotationViewModel` is the main-actor bridge between UI, Keychain/configuration, shared rotation state, patch notes, and widget reloads.
- `RotationStore` owns the app-group identifier, rotation snapshot, API-key handoff to the widget, refresh throttling, cached fallback, and suggested widget reload dates.
- `RotationSnapshot.projected(at:)` advances cached current/next data at a known boundary. Preserve projection behavior whenever rotation models or timelines change.
- Widgets must be cheap, deterministic, and timeline-driven. Do not add per-second timers, direct view-driven networking, or assumptions that the extension stays alive.
- A newly fetched rotation snapshot that changes shared state must cause the relevant widget timelines to reload.
- Patch notes and pick rates are app-only services with validated remote responses and cached fallback. Keep them out of `Shared/` unless the widget truly begins consuming them.

Do not duplicate shared rotation models in the widget target or create a second cache with competing keys. If a persisted model or cache key changes, provide an intentional migration or versioned fallback rather than silently stranding existing user data.

## Apex-Specific Visual Direction

The UI must read as an Apex companion immediately. Preserve and extend the existing visual language instead of applying a generic SwiftUI, productivity-app, or settings-dashboard aesthetic.

### Foundation

- The product is dark-first and currently forces dark appearance. Primary surfaces use near-black blue/charcoal, not flat system gray.
- `Color.apexRed` is the app's signature accent. Use it for live status, selection, primary action, slim edge treatments, and small areas of emphasis—not as a full-screen fill.
- Use layered black gradients over map art so data remains legible. Remote artwork must always have a purposeful `MapFallback` or equivalent.
- Prefer strong contrast, subtle white borders, restrained materials, and red atmospheric gradients. Decorative treatments must never reduce text contrast.
- Reuse `AppBackground`, `ScreenHeader`, `ErrorBanner`, `Color.apexRed`, and existing widget background/color primitives before creating new equivalents. Promote a repeated primitive into `DesignSystem/` instead of copying it again.

### Shape and composition

- Apex character comes from angular/slashed cues, clipped geometry, asymmetric corners, and strong editorial hierarchy. `ApexSlashPattern` and the uneven leader-card silhouette are established references.
- Large map art and decisive type should anchor important screens. Supporting information should be compact and scan-friendly.
- Use SF Symbols that communicate the actual mode or action. Decorative symbols must be hidden from accessibility.
- Avoid a screen made entirely from identical rounded rectangles. Rounded containers are allowed, but combine them with edge accents, image crops, asymmetric geometry, dividers, or varied hierarchy.
- Avoid generic glassmorphism, rainbow gradients, excessive glow, floating pill controls everywhere, or animation added only for spectacle.

### Typography and copy

- Use heavy/black weights for map names, rankings, and major headlines.
- Use uppercase, tightly scoped labels with generous tracking for eyebrows and status text such as `LIVE`, `NEXT`, or `CURRENT META`.
- Use monospaced digits for countdowns and changing numeric values. Use numeric content transitions where they improve continuity.
- Keep copy concise and player-aware: maps, rotations, queueing, ranked, pubs, the meta, and the Outlands. Do not force lore language into errors or settings where plain language is clearer.
- Preserve semantic Dynamic Type styles whenever possible. If a fixed size is justified for a display moment, constrain it with line limits/scaling and verify accessibility sizes.

### Motion and interaction

- Motion should communicate a live value changing, selection moving, content loading, or hierarchy transitioning.
- Prefer short, restrained system transitions and interruptible state changes. Do not animate continuously in a scrolling list.
- Pull to refresh, retry actions, links, tabs/sidebar selection, and widget configuration must remain obvious and native.
- Respect Reduce Motion for any nonessential custom animation.

### Required screen states

Every data-backed UI must deliberately handle:

- first load;
- populated success;
- empty response;
- recoverable error;
- stale/cached content plus refresh failure;
- offline behavior;
- missing or invalid API credentials where applicable;
- long map/legend names and large text sizes.

Do not replace useful cached content with an empty error screen merely because a refresh failed. Show the cached content and a non-blocking error when the architecture permits it.

## Swift and SwiftUI Engineering Rules

- The app and widget targets currently deploy to iOS 17. Do not use newer APIs without an availability guard and an iOS 17-quality fallback, unless the task explicitly raises the deployment target.
- Use four-space indentation and standard Swift naming: `UpperCamelCase` types and `lowerCamelCase` members.
- Prefer value-type, `Codable`, and `Sendable` models. Keep model behavior deterministic and independent of the UI.
- UI-observed state belongs on `@MainActor`. Long-running parsing, network, and persistence work should live in actors or otherwise be concurrency-safe.
- Prefer structured concurrency. Do not introduce detached tasks, manual thread hopping, or unstructured callbacks without a concrete need.
- Keep SwiftUI `body` declarations declarative. Move networking, persistence, validation, and nontrivial transformation out of views.
- Break large views into focused components, but avoid one-line wrapper types that obscure rather than clarify structure.
- Make state ownership explicit: `@StateObject` where a view creates a reference model, `@ObservedObject` where it receives one, and bindings for owned value state.
- Avoid force unwraps. A literal URL that is truly invariant may follow the existing convention, but new dynamic/provider data must be validated.
- Do not swallow meaningful errors with `try?` unless a fallback is intentional and the UI does not need to distinguish the failure.
- Keep previews deterministic. Use `RotationSnapshot.preview` or purpose-built fixtures; previews must not require real credentials or live network data.
- Prefer Apple frameworks already in use. Add a third-party dependency only when its maintenance and binary cost are clearly justified and record that reasoning in the handoff.

## Networking, Caching, and Provider Safety

External provider formats are untrusted and may change.

- Use HTTPS and validate the expected response type, HTTP status, host after redirects when relevant, payload size, and required fields.
- Set finite request timeouts and an identifiable `User-Agent` consistent with the app.
- Map provider failures to concise user-facing errors. Do not expose raw response bodies, keys, internal parsing details, or opaque system errors.
- Bound and validate parsed values. Existing legend parsing checks legend count, pick-rate range, and aggregate plausibility; preserve equivalent sanity checks when formats change.
- Cache successful provider results with an explicit freshness policy. If a refresh fails and a safe cache exists, return or display the cache.
- Respect refresh throttles and provider rate limits. A force refresh is not permission to hammer an endpoint.
- Keep time testable: calculations involving expiry, projection, countdown, or reload scheduling should accept a `Date`/clock input rather than scattering `Date.now` through core logic.
- If changing an endpoint or scraper, verify against the provider's current documented or observed format; do not code from memory alone.

## Widgets and Shared State

- Support the families declared by `ApexMapCheckWidgets`: system small, system medium, accessory inline, accessory circular, and accessory rectangular.
- System small uses the configured mode; system medium intentionally shows both pubs and ranked. Preserve that distinction unless product behavior is intentionally redesigned.
- Keep Lock Screen widgets legible in system-tinted contexts using `widgetAccentable()` and clear container backgrounds where appropriate.
- Timeline entries should include meaningful rotation boundaries, and the reload policy must respect the store's minimum refresh interval.
- Use the entry's date when projecting or presenting time-sensitive state so previews and future timeline entries remain deterministic.
- Keep widget layouts compact and bounded. Verify truncation, minimum scale factors, and accessibility summaries whenever content changes.
- Never assume the widget can read the app's Keychain item. Cross-target data must use the established app group or another explicitly configured shared entitlement.

## Accessibility and Adaptive Layout

Accessibility is a completion requirement, not a later polish pass.

- Supply useful labels for combined visual cards and widgets; do not let VoiceOver read decorative layers or fragmented duplicate values.
- Add hints for links or actions when the result is not obvious. Mark selected controls with the selected trait.
- Never communicate live/error/selection state by color alone.
- Maintain at least a 44-by-44-point practical touch target for interactive controls.
- Verify compact and large iPhone behavior for app UI changes. Avoid hard-coded widths that only fit one phone size.
- Verify Dynamic Type, long provider strings, and VoiceOver reading order. Use `ViewThatFits`, flexible frames, and meaningful wrapping before aggressive shrinking.
- Preserve safe-area behavior and enough bottom content inset above the compact tab bar.
- Widgets intentionally constrain Dynamic Type to preserve their bounded layout; changes still need to remain readable at every supported widget family and supported size in that range.

## Secrets, Privacy, and Configuration

- Never commit, print, paste into logs, or expose `ApexMapCheck/Secrets.plist` or any API key. The file is intentionally ignored by Git.
- Do not open or inspect a real secrets file unless a task specifically requires configuration diagnosis; even then, never report its values.
- `Secrets.example.plist` must contain placeholders only.
- User-entered credentials belong in `KeychainStore`. The existing app-group API-key copy exists so the widget can refresh; treat changes to this behavior as security-sensitive and preserve least exposure.
- Do not include credentials in URLs, error messages, fixtures, previews, screenshots, commits, or test recordings.
- Preserve the app-group identifier and matching entitlements across both targets unless the task explicitly performs a coordinated migration.
- Before committing, inspect the diff for secrets and personal data, not only the list of filenames.

## Xcode Project Safety

The repository depends on Xcode Cloud compatibility:

- `ApexMapCheck.xcodeproj/project.pbxproj` must keep `objectVersion = 77`.
- Xcode may rewrite it to `110`. The repository's pre-commit and pre-push hooks normalize/block that format. Enable them with `git config core.hooksPath .githooks` in a fresh clone.
- Do not hand-edit opaque project identifiers or reorder the project file for cosmetic reasons.
- Because folders are synchronized, avoid project-file churn for ordinary source additions. Edit the project only for real target membership exceptions, build settings, capabilities, resources outside synchronized roots, dependencies, or new targets.
- After any project-file change, inspect the diff closely, confirm object version 77, and build both the app and embedded widget through the main scheme.
- Keep bundle identifiers, app-group entitlements, version numbers, and signing settings coordinated. Do not change the development team or signing identity as a drive-by fix for a local build.

## Tests and Verification

There is no test target yet. For a small UI-only change, do not create an entire test target solely to satisfy a checkbox. When adding meaningful parsing, cache, projection, scheduling, or error-mapping behavior, prefer adding XCTest coverage; if the first test target is introduced, place it under `ApexMapCheckTests/` or `ApexMapCheckWidgetsTests/` and keep project format 77.

Name tests by behavior, for example:

```swift
func testFetchReturnsCachedSnapshotWhenOffline()
func testProjectionPromotesNextMapAfterBoundary()
func testReloadDateNeverViolatesMinimumRefreshInterval()
```

Use deterministic fixtures. Do not call live services, rely on a real API key, share mutable user defaults, or depend on wall-clock time in unit tests.

### Minimum command-line validation

From the repository root:

```sh
xcodebuild -project ApexMapCheck.xcodeproj -scheme ApexMapCheck \
  -destination 'generic/platform=iOS Simulator' \
  -configuration Debug CODE_SIGNING_ALLOWED=NO build
git diff --check
```

The main scheme builds the app and embedded widget extension. If tests exist, run them with an explicit available simulator destination rather than relying on Xcode's default device.

Also perform targeted checks appropriate to the change:

- **Shared/model/API/cache change:** exercise parsing and fallback behavior; verify app and widget compilation; verify cache migration/projection and boundary dates.
- **App UI change:** run or preview on compact and large iPhones; inspect loading, success, empty, error, cached/offline, and credential states that are affected.
- **Widget change:** preview/run every affected family, including placeholder/snapshot and unavailable-data states.
- **Accessibility change:** inspect large Dynamic Type and VoiceOver labels/order, not only the default visual layout.
- **Project/configuration change:** inspect `project.pbxproj`, entitlements, target membership, bundle settings, and object version.

A compile alone is not sufficient evidence for a material visual change. Use SwiftUI previews or a Simulator for visual inspection. If runtime tooling is unavailable, report that the visual portion remains unverified.

## Definition of Done

Before handing work back, confirm all applicable items:

- The requested behavior is complete, with no placeholder or knowingly dead path.
- New files are in the correct target-owned directory.
- App/widget/shared boundaries remain intact.
- Apex visual language is preserved on every new or changed product surface.
- Loading, empty, error, cached/offline, and credential states were considered.
- Accessibility and supported iPhone layouts were considered and, for UI changes, exercised.
- Relevant builds and tests pass, and `git diff --check` is clean.
- `project.pbxproj` still uses object version 77.
- The diff contains no secret, unrelated edit, build output, or user-specific Xcode state.
- Provider attribution and the EA/Respawn non-affiliation statement remain where applicable.
- The final handoff summarizes user-visible behavior, affected targets, validation actually run, and any remaining risk or unverified condition.

## Commits and Pull Requests

- Use short imperative commit subjects, such as `Fix map card scaling and mode labels`.
- Keep commits cohesive and do not mix unrelated cleanup with product work.
- Pull requests must explain user-visible behavior, name affected targets, call out API/cache/project-format implications, and list exact build/test evidence.
- Attach before/after screenshots for material app UI changes and representative previews for widget changes.
- Never bypass a failing compatibility hook. Correct the project format or underlying issue, then commit the correction.
