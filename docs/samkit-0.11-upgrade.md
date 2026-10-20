# Preen: SamKit 0.11 upgrade

Preen moves from SamKit 0.6.0 to 0.11.0 (`c0aba294627798dce493bcda8a269bf453689494`). `project.yml`, the XcodeGen project and `Package.resolved` agree; Sparkle remains at 2.10.0.

## Adopted

- One app-owned SamKit `LoginItem` supplies Settings and Welcome. The local status enum and log-only registration wrapper are removed, as is Welcome's 1.5-second polling loop. Actual system status refreshes when the app becomes active.
- General uses `LoginItemToggle`, including approval guidance, a System Settings action, retained errors and retry. Welcome retains its existing steps, normal wording and layout, with the registration error and a retry action when needed. A registration awaiting approval stays incomplete.
- General refreshes clipboard authorization when the app becomes active, as well as on appearance (audit D3). The existing guard against querying the pasteboard during an outstanding approval read remains intact.
- The retained Settings controller is created at launch and handles reopen through `handleReopen()`. Preen has no primary content window, so an existing titled window comes back first, a minimized one is restored, and otherwise Settings opens. Menu and Command-comma use the same controller.
- The resolved kit supplies the non-key automatic Welcome/What's New fix and Settings display/Space placement. There was no app-local onboarding focus workaround to remove. Launch eligibility and explicit activation remain unchanged.
- Feedback receives the kit's system UI-effects sound policy. Preen had no additional local sound gate.

## Kept and deferred

The status item retains its native `NSMenu`, its custom feather and existing menu behavior. There is no panel to migrate, no `MorphSurface` delay to replace, and no transient surface state machine to adopt. Rules use a reconstructible cache with bundled fallback; this upgrade does not introduce `StoreFile` or rewrite that cache. The audit's rule-compilation work (D1), in-flight inspection/pause race (D2), exception commands and localization opportunities remain separate work.

## Clipboard-safe verification

Debug launches with `--verify-ui` route the cleaner's watcher, access-state queries and Welcome's sample action to one unique named pasteboard. Release builds always use the general pasteboard. This is a cleaner verification seam, not system-wide clipboard isolation: SamKit About's Copy version button, native Copy/Cut/Paste, text-selection copying and Services may still use system pasteboards. Do not invoke those routes during checks. No real clipboard read, write, content snapshot or permission change is needed.

Launch only the disposable Debug app (`com.samunderwood.Preen.dev`, Preen Dev), with `--verify-ui -updatesRulesAutomatically NO -SUEnableAutomaticChecks NO`, under `/tmp/gui-lock.d`. For Welcome/notes scenarios, stop the Dev app, save its sandbox preference domain, set typed test values for `welcomePending`, `welcomeVersion` and `lastOpenedVersion`, then restore that domain after quitting. A launch-argument string is not a Boolean for the kit’s typed `welcomePending` check. Do not import production preferences or enable/disable a real login item as a test.

## Verification

- Debug and Release builds, arm64 destination: passed with no compiler warnings. The final Debug rebuild restores the normal application signature after Xcode's test action. A lazy opaque-view initializer warning was removed by constructing the Settings controller directly in the existing launch callback.
- `swift test` for PreenCore: 32 tests in four suites passed.
- Xcode scheme test action: 32 tests passed; the result bundle reports no runtime warnings. Xcode itself printed an internal `IDELaunchSession` completion-handler warning.
- `swift test` against the resolved SamKit 0.11.0 checkout: 167 tests in twelve suites passed, including login errors/retry/approval, activation refresh and observer lifetime, reopen routing and onboarding policy coverage.
- GUI, macOS 27.0.1, under the machine-wide lock: verified the exact Debug path and PID; observed General with the shared login row and its real `.notFound` explanation/“Try Again” for the temporary build. Settings opens through the main menu, status-menu action, Command-comma and reopening the app with no window. Minimizing and reopening changes `AXMinimized` from 1 back to 0 on the same window. A General window screenshot was viewed.
- Welcome was inspected through the native app connection, including its unchanged normal content and the login failure detail. Pressing “Copy Link” on the private pasteboard advanced Try It to “Removed utm_source, utm_medium, fbclid”. “Not Now” dismissed Welcome. Eligible 1.0 → 1.0.1 What’s New content was visually inspected. Both screens’ actual native window captures were viewed.
- Focus verification is **unverified**: repeated foreground-probe attempts could not establish a stable active test app (`beforeFront=false`), so they cannot demonstrate preserved typing focus or a focus regression. Normal scripted activation was not sufficient. Current-Space visibility also varied during those attempts; native app capture could still inspect the windows. No claim of successful full-screen/Space or foreground activation testing is made.
- The first System Events app-name lookup was ambiguous between installed Preen and Preen Dev. It reached the installed menu/Settings; its route evidence was discarded and the checks repeated with the exact Dev PID and app path. No clipboard command was invoked there; opening that menu can refresh the installed app’s clipboard-access metadata through its existing delegate. No real clipboard contents were read, copied, restored or written by verification.
- Actual login registration/approval changes, real clipboard permission transitions, multi-display/disconnected-display placement, physical audio/haptics and a cold App Intent launch remain unverified. Registration/approval/failure recovery logic is covered by the resolved kit tests. The native status-menu pointer-opening/foreground path was not established; the selected menu action and resulting Settings window were observed.
- Temporary Dev preference markers were restored after the checks; production preferences, login registration and clipboard permissions were not changed.

## Cleanup

The disposable Dev app and focus probe exited. Task-owned Debug/Release builds, package scratch folders, focus probe and Xcode result bundle were removed after extracting the test summary. Each discovered app bundle was submitted for Launch Services unregistration; some unlaunched Sparkle copies/duplicate framework paths returned `-10814` (“failed to scan”). The final Launch Services dump contains no `preen-samkit` path. The GUI lock was released. Logs, the extracted Xcode summary, AX snapshots and the General screenshot remain under `/tmp/preen-samkit-*`; Welcome and What's New captures were viewed in the native app connection.

## Independent review

A fresh Codex Sol reviewer inspected the app diff against `9b238b03b5a7dbf85a1692642762eeb94867d630` and the resolved kit APIs. It identified that About/native clipboard commands bypass the private cleaner pasteboard. The verification scope and excluded actions above explicitly account for that limit; no GUI action had run before the finding. A second fresh review accepted the explicit protocol, found no other automatic general-pasteboard access in the tested paths, and reported no actionable findings. The final small compiler fix replaces forced lazy initialization in the launch callback with direct construction there; presentation timing is unchanged.

Implementation commit: `c458745` (`Adopt SamKit 0.11 login state and reopen routing`). Both reviews covered the cumulative app diff from `9b238b0`; the final direct Settings initialization is a small compiler-only follow-up at the same launch point.
