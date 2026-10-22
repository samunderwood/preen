# Preen

Preen is a free, open-source menu bar app for macOS 26 or later. It removes tracking parameters and redirect wrappers from copied links, shows what changed, and lets people restore the original.

## Build, test and run

Run these from the repository root with Xcode 27.1 selected. The app needs access to the private SamKit package.

`Preen.xcodeproj` is committed. `xcodegen generate` was checked and leaves it unchanged; the release script requires this.

Build (verified with ad-hoc signing):

```sh
xcodebuild -project Preen.xcodeproj -scheme Preen -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/preen-ci-check.noindex \
  -scmProvider system CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM='' build
```

Tests (verified):

```sh
xcodebuild test -project Preen.xcodeproj -scheme Preen -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath /tmp/preen-ci-check.noindex \
  -scmProvider system CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=''
swift test --package-path Packages/PreenCore
```

Run (not run: a normal launch starts monitoring the system clipboard). For UI checks, follow the procedure in `docs/samkit-0.11-upgrade.md`.

```sh
open /tmp/preen-ci-check.noindex/Build/Products/Debug/Preen.app
```

## Debug identity

- Bundle ID: `com.samunderwood.Preen.dev`, rather than the release's `com.samunderwood.Preen`.
- The bundle is `Preen.app`, but its display name is `Preen Dev`.
- It is sandboxed. Its preferences and downloaded rules live in its own container, `~/Library/Containers/com.samunderwood.Preen.dev/`; rules are under `Data/Library/Application Support/Rules/`.
- The login item uses SamKit's `LoginItem` and `SMAppService.mainApp`, so the Debug app has its own registration. There is no separate login helper target.
- Its Service is `Clean Links (Preen Dev)`, with port name `Preen Dev`. No URL scheme is declared.
- It is a menu bar app (`LSUIElement`); reopening it shows Settings.

## Tests and rules

- `PreenTests` is an unhosted unit-test target. It compiles the clipboard watcher directly and gives it its own test pasteboards, so tests do not launch the app or clean the system clipboard.
- `Packages/PreenCore` has no dependencies. Its `PreenCoreTests` run both through the Xcode scheme and independently with SwiftPM.
- `scripts/update-rules.sh` refreshes both the bundled rules and the matching test fixtures. Run the tests afterwards.

## Releases

`scripts/release.sh` calls SamKit's shared release script using `scripts/release.conf`. The bundled changelog is `Preen/Resources/CHANGELOG.md`.

The appcast is <https://updates.samunderwood.co.uk/preen/appcast.xml>.

Use the `mac-app-release` skill for releases and release notes.

## CI

`.github/workflows/ci.yml` builds and tests the committed project, then runs the PreenCore package tests. It needs the repository's `SAMKIT_DEPLOY_KEY` secret, a read-only deploy key on `samunderwood/samkit`.

Fork pull requests cannot fetch SamKit because they receive no repository secrets; a maintainer will build and test those changes.

## Not for release notes

Debug-only tools and settings, hidden or test commands, owner or tester switches, and anything not yet released must not appear in the changelog or release notes. Sam keeps the specific list privately; do not write it in this public repository.
