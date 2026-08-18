# App Store Build 13 Truthfulness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce RDesk iOS 2.1.0 (13) with no user-reachable placeholder features and with App Store, review-note, support-page, and in-app capability claims aligned to the shipped behavior.

**Architecture:** Remove the local-only chat surface instead of completing a new network feature during review remediation, and remove the static shortcut guide because the active Flutter HTTP path does not transmit the advertised key combinations. Keep implemented remote-control, file, clipboard, quality, display, and viewer-local controls unchanged. Treat the repository documents as the source for the next ASC update, but keep all real review credentials outside Git.

**Tech Stack:** Flutter/Dart widget tests, Flutter analyzer and iOS IPA build, static HTML, Bash/SSH deployment, Git.

**Spec:** `docs/app-review-response.md`

## Global Constraints

- The active mobile connection path is the Flutter HTTP bridge; Rust QUIC/Noise/P2P stubs must not be advertised as active behavior.
- Windows is controller-only in current distribution material; Windows hosting/input is not implemented.
- iOS hosting is screen-share-only and cannot accept remote touch input.
- Mobile remote input supports tap, long press, single-pointer drag/path, text, Enter/Delete, and explicit actions; pinch zoom and canvas rotation are viewer-local.
- Real App Review account and demo-host credentials must never be committed.
- Do not modify ASC metadata, send Apple a message, upload build 13, or resubmit without the user's final action-time confirmation.
- Work on the explicitly authorized current `master` checkout, preserve unrelated changes, verify before each commit, and push only after the complete local change passes validation.

---

### Task 1: Remove user-reachable placeholder features

**Files:**
- Create: `flutter_client/test/review_truthfulness_test.dart`
- Modify: `flutter_client/lib/app.dart`
- Modify: `flutter_client/lib/src/widgets/remote_control_panel.dart`
- Modify: `flutter_client/lib/src/widgets/desktop_viewer_layout.dart`
- Modify: `flutter_client/lib/src/widgets/desktop_viewer_sidebar.dart`
- Modify: `flutter_client/lib/src/screens/remote_desktop_screen.dart`
- Modify: `flutter_client/lib/src/screens/profile_screen.dart`
- Modify: `flutter_client/lib/src/utils/router.dart`
- Modify: `flutter_client/lib/src/services/rdesk_bridge_service.dart`
- Delete: `flutter_client/lib/src/screens/chat_screen.dart`
- Delete: `flutter_client/lib/src/screens/shortcut_guide_screen.dart`
- Delete: `flutter_client/lib/src/providers/chat_provider.dart`
- Delete: `flutter_client/lib/src/models/chat_message.dart`

**Interfaces:**
- Consumes: existing `RemoteActionSheet`, `ProfileScreen`, `RDeskApp`, `SessionProvider`, and `appRouter`.
- Produces: a remote action sheet with only implemented actions and a profile quick grid with no unsupported shortcut guide.

- [x] **Step 1: Write the failing widget tests**

```dart
testWidgets('远控操作面板不显示仅本地保存的会话聊天', (tester) async {
  final session = SessionProvider();
  addTearDown(session.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: RemoteActionSheet(
            sessionId: 'review-session',
            onDisconnect: () {},
            onFileManager: () {},
            onChat: () {},
            onToggleToolbar: () {},
            onRemoteAction: (_) async {},
            onPushClipboard: () async {},
            onPullClipboard: () async {},
          ),
        ),
      ),
    ),
  );
  expect(find.text('文件传输'), findsOneWidget);
  expect(find.text('会话聊天'), findsNothing);
});

testWidgets('我的页不显示未实现的快捷键入口', (tester) async {
  SharedPreferences.setMockInitialValues({});
  appRouter.go('/me');
  await tester.pumpWidget(const RDeskApp());
  await tester.pumpAndSettle();
  expect(find.text('操作手势'), findsOneWidget);
  expect(find.text('快捷键'), findsNothing);
});
```

- [x] **Step 2: Run the tests and verify RED**

Run: `cd flutter_client && flutter test test/review_truthfulness_test.dart`

Expected: both tests fail because `会话聊天` and `快捷键` are currently visible.

- [x] **Step 3: Make the minimal UI removal**

Remove the `会话聊天` action row and the profile `快捷键` quick item without changing implemented controls.

- [x] **Step 4: Run the tests and verify GREEN**

Run: `cd flutter_client && flutter test test/review_truthfulness_test.dart`

Expected: 2 tests pass.

- [x] **Step 5: Refactor away dead chat/shortcut code**

Remove `onChat` constructor parameters and route callbacks, remove the two routes/imports, remove `ChatProvider` from `MultiProvider`, remove chat persistence methods/imports from `RdeskBridgeService`, and delete the four orphan files. Update the test fixture to omit `onChat` after the production interface no longer accepts it.

- [x] **Step 6: Verify the refactor stays GREEN**

Run: `cd flutter_client && flutter test test/review_truthfulness_test.dart test/widget_test.dart`

Expected: all tests pass and `rg -n "ChatProvider|ChatMessage|ChatScreen|onChat|/chat/|shortcut-guide|ShortcutGuideScreen|会话聊天|快捷键" flutter_client/lib` returns no user-reachable removed feature.

---

### Task 2: Align every review-visible capability statement

**Files:**
- Modify: `deploy/support.html`
- Modify: `docs/app-store-submission.md`
- Modify: `docs/app-review-response.md`

**Interfaces:**
- Consumes: the shipped behavior established by Task 1 and existing truthful-description draft in `docs/app-store-submission.md`.
- Produces: one consistent capability boundary for the public support page, future ASC description, and build 13 review response/notes.

- [x] **Step 1: Correct the public support page**

Replace the Windows-host instruction with this exact supported-host guidance:

```html
<p>如果需要完整的远程操控，请把 Android 或 macOS 设备作为被控端。Windows 当前仅支持作为主控端。</p>
```

- [x] **Step 2: Make the submission document current**

Set the source-of-truth candidate to `2.1.0 (13)`, add build 11/12 rejection history, record build 13 as prepared but not uploaded, keep the corrected description that says iOS is screen-share-only, and mark chat/shortcut claims as removed rather than implemented.

- [x] **Step 3: Rewrite the active review response and note sections**

Record the 2026-08-18 third rejection, explain the confirmed mismatches without claiming Apple named a specific trigger, remove `会话聊天` from the control list, remove the sentence that every remaining control necessarily sends a host request, and limit platform claims to:

```text
Android and macOS hosts accept remote control. An iOS host shares its screen only. Windows is controller-only in the current release material.
```

Use `[REDACTED_IN_REPOSITORY]` for any credential that exists only in ASC.

- [x] **Step 4: Review the prose diff and forbidden claims**

Run:

```bash
git diff --check
rg -n "Windows、macOS、Android、iOS 之间互控|多点触控手势|Windows 或 macOS 设备作为被控端|every other control results in a request|会话聊天 \(Chat\)" deploy/support.html docs/app-store-submission.md docs/app-review-response.md
```

Expected: `git diff --check` succeeds; any remaining matches are clearly labeled historical evidence rather than active submission copy.

---

### Task 3: Bump and verify iOS build 13

**Files:**
- Modify: `flutter_client/pubspec.yaml`
- Modify/regenerate: `flutter_client/ios/Flutter/Generated.xcconfig`

**Interfaces:**
- Consumes: the Flutter tree from Tasks 1-2.
- Produces: a locally verified `2.1.0 (13)` IPA candidate; no ASC upload.

- [x] **Step 1: Bump the build number**

Change `version: 2.1.0+12` to `version: 2.1.0+13`, then run `cd flutter_client && flutter pub get` so generated configuration records build 13.

- [x] **Step 2: Format and run focused tests**

Run:

```bash
cd flutter_client
dart format lib test/review_truthfulness_test.dart
flutter test test/review_truthfulness_test.dart test/widget_test.dart test/canvas_rotation_test.dart test/remote_canvas_pointer_test.dart test/session_view_only_test.dart test/connection_history_dedupe_test.dart
```

Expected: all focused tests pass.

- [x] **Step 3: Run static analysis**

Run: `cd flutter_client && flutter analyze --no-fatal-infos`

Expected: exit 0 with no errors or warnings. Existing informational lints may still be listed;
plain `flutter analyze` treats those infos as fatal in the current toolchain.

- [x] **Step 4: Build the signed IPA candidate**

Run: `cd flutter_client && flutter build ipa --release`

Expected: exit 0, `build/ios/ipa/RDesk.ipa` exists, and both Runner and Broadcast Extension report `CFBundleShortVersionString=2.1.0` and `CFBundleVersion=13` when inspected from the archive/IPA.

- [x] **Step 5: Install on an available iPhone and smoke test**

Use `scripts/reinstall_ios.sh [device-id]` when an iPhone is connected. Verify the app opens, `我的` has no `快捷键`, a connected remote session's `操作` sheet has no `会话聊天`, and existing control/file/clipboard entries remain visible. If no iPhone is available, report this as an explicit unresolved verification boundary instead of substituting an emulator claim.

---

### Task 4: Deploy and verify the corrected support page

**Files:**
- Deploy source: `deploy/support.html`
- Production target: `/data/website/rdesk/support.html` on `root@101.37.21.147`

**Interfaces:**
- Consumes: corrected static HTML from Task 2.
- Produces: the live support URL used by ASC, with recoverable server backup.

- [x] **Step 1: Validate local HTML and inspect the current remote file**

Run `tidy` if available, otherwise parse locally with a standard HTML parser; then read the remote target metadata and checksum without modifying it.

- [x] **Step 2: Back up and deploy only the support page**

Create a timestamped sibling backup on the server, copy only `deploy/support.html` to the production target, and do not restart unrelated services.

- [x] **Step 3: Verify the live URL**

Run `curl -fsS https://qisw.top/rdesk/support` and confirm it says Android/macOS are controllable hosts, Windows is controller-only, and it no longer recommends Windows as a controlled host.

---

### Task 5: Final verification, commit, and push

**Files:**
- Review all files changed by Tasks 1-4.

**Interfaces:**
- Consumes: verified build 13 source, tests, IPA evidence, and live support-page readback.
- Produces: committed and pushed repository state; ASC remains untouched.

- [x] **Step 1: Review the complete diff and requirement checklist**

Run `git status --short`, `git diff --stat`, `git diff --check`, and inspect the full diff for removed functionality, truthful copy, version 13, credential leakage, and unrelated edits.

- [x] **Step 2: Re-run the final verification suite**

Freshly run the focused Flutter tests, `flutter analyze --no-fatal-infos`, build/IPA metadata checks, public support-page readback, and `git diff --check` immediately before committing.

- [x] **Step 3: Commit the verified change**

Stage only the plan, Flutter removals/tests/version files, submission/review docs, and support page. Use a conventional Chinese commit message describing the App Review truthfulness remediation.

- [x] **Step 4: Push to `origin master`**

Push only after the commit is verified and confirm the remote branch contains the new commit.

- [x] **Step 5: Stop at the external-review gate**

Report the exact state as `build 13 local candidate prepared` or `build 13 installed/verified` according to evidence. Do not call it uploaded, submitted, approved, or public. Ask for final confirmation before editing ASC, replying to Apple, uploading, or resubmitting.
