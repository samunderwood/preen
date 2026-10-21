# Audit fixes, October 2026

Fixes for the Preen 1.0.1 audit (`9b238b0`). D3 (Settings kept stale permission and login state) and D4 (failed login-item changes went unexplained) were fixed by the SamKit 0.11 adoption in `c458745`; see `docs/samkit-0.11-upgrade.md`.

## Batch 3

### D1: Rule validation and compilation blocked the main actor — fixed

**Cause.** `AppModel` read, checked and compiled both rule sets synchronously on the main actor: once while the delegate was being created at launch, and again after every rule download. A downloaded file was compiled twice, once by `RuleDownloader.saved` to check it and again to build the cleaner.

**Change.**
- `Packages/PreenCore/Sources/PreenCore/RuleSource.swift`: `RuleDownloader.load(bundled:)` (`@concurrent`) reads the downloaded rules, keeps a good file's compiled result rather than compiling it again, falls back to the bundled copy of any list whose download is missing or bad, and returns a `Sendable` `RuleSet` with each list's download date. `loadNow(bundled:)` does the same on the caller's thread. The public `saved(_:)` is replaced.
- `Preen/App/AppModel.swift`: loads start with `Task.immediate`, so the first one begins while the app is still launching instead of after. The compiled rules are applied in one synchronous step on the main actor: cleaner, current site exceptions and rule status together. The rules in use stay until the new ones are ready, and a load that finishes after a newer one is dropped. The daily update check runs once the first rules are in use rather than before, since until then nothing is known about their age.
- `Preen/Intents/CleanLinksIntent.swift`, `Preen/Support/Preferences.swift`: the Shortcuts action waits for the first load; the bundled rules are found by folder.

**Before the rules first load.** A link copied in that moment is held, and cleaned once they arrive, through the same write as any other copy. It is left alone if something newer has been copied or Preen has been paused by then. Clean Clipboard Now behaves the same way. The Shortcuts action waits for the rules. The Services menu has to answer before it returns, so if it asks first, which can only happen when it launched Preen, it compiles the rules on the spot on the main actor, as every load did before.

**Measured.** A scratch probe ran the old and new loading paths against the real bundled rule files (2,664 AdGuard rules and 799 ClearURLs rules), six runs each, with no pasteboard access, on macOS 27.0.1.

| | Main actor blocked, before | Main actor, after (longest gap) | Background work, after |
| --- | --- | --- | --- |
| Downloaded rules, Debug | 76–87 ms | 0.5–0.6 ms | 40–45 ms |
| Downloaded rules, Release | 51–58 ms | 0.5–0.8 ms | 26–30 ms |
| Bundled rules only, Debug | 42–46 ms | 0.6–1.1 ms | 37–42 ms |
| Bundled rules only, Release | 24–27 ms | 0.5–0.6 ms | 22–23 ms |

"After" is the longest the main actor went without running while a load was in progress, sampled with a main-actor heartbeat, including applying the result. The audit's probe measured 99–175 ms for the same work; today's runs were faster on the same Mac.

**Tests.** `RuleLoadingTests` in PreenCore, with real files in a temporary folder: bundled rules before any download, good downloads used with their dates, and a bad download falling back to the bundled copy of that list only.

### D2: Pausing didn't stop an automatic inspection in flight — fixed

**Cause.** `ClipboardWatcher.stop()` removed the timer and app observer but left a running inspection alone. Once link detection answered, the copy was handed over and could be rewritten after Pause had taken effect. The change-count check only protects a newer copy.

**Change.** `Preen/Clipboard/ClipboardWatcher.swift`: each copy records the stretch of watching it was found in (`Copy.watch`), or none for a read on request. `stop()` starts a new stretch and cancels the inspection, leaving the `inspecting` flag set until that read actually finishes, since a read waiting for macOS's approval still holds the pasteboard. An inspection from an earlier stretch stops as soon as link detection answers, before the copy is read, and is not handed over; `write(_:title:replacing:)` refuses a copy from an earlier stretch before the existing change-count check. This also covers a copy held until the rules load. Clean Clipboard Now's copies carry no stretch, so it still works while paused or after a copy from an excluded app. The watcher now takes its pasteboard and link detection as parameters, with the app's existing ones as defaults.

**Tests.** A new `PreenTests` target runs without the app, compiling `ClipboardWatcher.swift` in directly, so no test starts Preen's clipboard monitoring. Each test uses its own named pasteboard. Link detection is held open by the test to pause mid-inspection. Two tests failed before the fix (`pausingStopsAnInspectionInFlight`, `aCopyFromBeforeAPauseIsNeverWritten`), and three guard existing behaviour: a copied link is cleaned, Clean Clipboard Now works while paused, and a newer copy is never replaced.

### Verification

- Xcode scheme test action: 40 tests passed (35 PreenCore, 5 watcher). `swift test` for PreenCore: 35 passed.
- Debug and Release builds, arm64: no compiler warnings.
- Preen Dev (`com.samunderwood.Preen.dev`), launched by path with `--verify-ui` (private pasteboard) and automatic rule and app updates off, under the machine-wide GUI lock. Welcome was enabled with test preference values, restored afterwards. With Preen paused from General, Welcome's Copy Link left the sample link alone for four seconds. After resuming, the same action showed "Removed utm_source, utm_medium, fbclid". Settings ▸ Rules showed the counts and dates from the background load ("2,664 rules, updated 2 days ago"; "799 rules"). Update Now downloaded both lists and the pane changed to "updated now" within about a second. The installed Preen kept running untouched throughout.

**Not verified.**
- The in-flight pause race itself was not reproduced live: it can't be timed reliably against real link detection without the general clipboard. The held-detection tests cover it.
- A copy made in the moment before the first load isn't observable live, since the load finishes within about 40 ms of launch.
- The Services fallback compile was not exercised. A cold launch from the Services menu and the Shortcuts action in Shortcuts.app weren't run.
- No hitch trace was recorded. The measurement above times the work at the main actor, not frames.
- `AppModel`'s publication logic (holding an early copy, dropping a late load, the Services fallback) has no unit tests: the model needs the app host, which would watch the clipboard. Both reviewers traced it by hand.

### Review

Both reviews covered `622d762..512e32c`. Each reviewer ran the 40 tests in a temporary build folder and launched no app.

- **Claude Opus, fresh session.** No high or medium findings. Low: after a pause, an inspection still read the copy once detection answered and only then discarded it, which could bring up macOS's approval question for a paused Preen. Fixed in `bc11146`: the inspection now stops before reading. Its remaining note, missing `AppModel` tests, is recorded above.
- **Codex GPT-6 Astra, extra-high reasoning.** P2: the Services fallback published as load 0, so a launch load that read older files could replace it after Update Now had saved newer ones. Reaching it needs Update Now and a Services request within the first load's ~40 ms, but the fix is small. Fixed in `76b31a1`: the fallback takes its number from the same sequence as background loads. No other findings.

The two fixes were checked with the full suite (40 passed) and Debug and Release builds without warnings. Both are small and follow the reviewers' suggestions, so they weren't reviewed again.

### User-visible changes

- Preen starts and refreshes its cleaning rules without holding up the menu bar or your copies.
- A link copied while Preen is still starting up is cleaned as soon as it's ready.
- Pausing Preen now takes effect at once, even for a link copied a moment before.
