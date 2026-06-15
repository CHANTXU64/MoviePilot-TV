# OCR Review Safety Fix Handoff Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Continue the OCR zero-review cleanup on `MoviePilot-TV` in small TDD commits, with the main agent controlling scope and subagents doing bounded read-only review.

**Architecture:** Work in the existing isolated worktree and branch, fix one verified issue at a time, and commit after each completed slice. Treat OCR reports as noisy inputs: every finding must be verified against current Swift code, `.agents/ReviewPlan.md`, the final-review prompt, and where relevant the MoviePilot Web frontend behavior before changing code.

**Tech Stack:** Swift 6, SwiftUI, tvOS, XCTest via `xcodebuild`, Keychain Services, Git worktrees.

---

## Current State

- Worktree to continue in: `/private/tmp/MoviePilot-TV-fix-ocr-phase1-safety`
- Branch: `ai/fix-ocr-phase1-safety`
- Base: `origin/main` at `2af395c`
- Do not edit the main worktree at `/Users/robot/code/MoviePilot-TV` for this task.
- Do not push, open PRs, or merge unless the user explicitly asks later.
- User requested: "先写测试吧" and "改完一个 Commit 一个".

Completed commits on this branch:

```text
082aed9 [AI] fix/credentials: prevent access token plaintext fallback
3afbb31 [AI] fix/credentials: prevent login credential plaintext fallback
```

Completed behavior:

- `APIService.token` no longer writes `accessToken` to `UserDefaults` when secure storage rejects a save.
- `storedUsername` and `storedPassword` no longer write plaintext fallback values to `UserDefaults` when secure storage rejects a save.
- Successful secure saves still remove old `UserDefaults` migration residue.
- `nil` assignment still deletes secure items and removes related `UserDefaults` keys.
- Added `CredentialStore` protocol and made `KeychainHelper` conform.
- Added DEBUG-only `APIService.replaceCredentialStoreForTesting(_:)` and `APIService.setStoredCredentialsForTesting(username:password:)`.
- Added `MoviePilot-TV-Tests/CredentialPersistenceTests.swift` with explicit failing-store tests, avoiding dependence on real Keychain availability.

Verification already run after commit `3afbb31`:

```bash
xcodebuild -resolvePackageDependencies \
  -project MoviePilot-TV.xcodeproj \
  -scheme MoviePilot-TV \
  -skipPackagePluginValidation

xcodebuild clean build \
  -project MoviePilot-TV.xcodeproj \
  -scheme MoviePilot-TV \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation

xcodebuild test \
  -project MoviePilot-TV.xcodeproj \
  -scheme MoviePilot-TV \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -skipPackagePluginValidation
```

Latest full test result: `Executed 48 tests, with 10 tests skipped and 0 failures`.

## Required Context To Read First

- `.agents/prompts/final-review.md`
- `.agents/ReviewPlan.md`
- OCR reports from the report worktree or branch:
  - Worktree: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports`
  - Branch: `ai/ocr-zero-review-reports`
  - Directory: `docs/ocr-zero-review/`

Read only the OCR report needed for the current slice. Do not bulk-load every report unless necessary.

Priority OCR slices already identified from the previous review pass:

```text
1. APIService / KeychainHelper credential security
2. Models decoding / avatar fallback
3. SubscribeSheet mistaken rollback behavior
4. ResourceResultViewModel SSE lifecycle and error handling
5. DownloadTaskViewModel crash or stale request overwrite
```

Credential plaintext fallback is now handled by commits `082aed9` and `3afbb31`. Continue by checking whether the credential-security slice still has a separate verified issue, such as Keychain query correctness or status UI/logging, before moving to Models.

## Global Rules For The Next AI

- Communicate with the user in Chinese.
- Use TDD for every behavior change: write the failing XCTest first, run it to observe the expected failure, implement the minimal fix, then rerun tests.
- Use subagents for bounded read-only review after each slice. Ask them for findings with file/line references and treat their output as suggestions to verify, not orders.
- Keep each commit narrow. One fixed issue plus its focused tests per commit.
- Use commit messages in this format:

```text
[AI] <type>/<scope>: <summary>
```

- Do not use `swift build`, `swift test`, or `swift package resolve` as project validation.
- Do not change `.agents/ReviewPlan.md` unless the user explicitly asks to archive review progress.
- Do not broaden into unrelated refactors, even if OCR mentions many style issues.
- Do not add TV-only backend compatibility behavior unless MoviePilot Web differs and the TV code is clearly wrong.
- If a command fails because Git metadata is outside the sandbox, rerun the same Git command with escalation. Do not work around it by editing `.git` manually.

## Task 1: Finish Credential-Security Slice Triage

**Files likely involved:**
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch01-api-service.raw.md`
- Read: `MoviePilot-TV/Services/APIService.swift`
- Read: `MoviePilot-TV/Services/KeychainHelper.swift`
- Read if UI status is mentioned: `MoviePilot-TV/ViewModels/SystemViewModel.swift`
- Test: `MoviePilot-TV-Tests/CredentialPersistenceTests.swift`

- [ ] **Step 1: Read only the relevant OCR report**

```bash
sed -n '1,260p' /private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch01-api-service.raw.md
```

- [ ] **Step 2: Verify whether a real unfixed credential bug remains**

Check current code, not memory:

```bash
rg -n "accessToken|username|password|KeychainHelper|UserDefaults|CredentialStore|print\\(" MoviePilot-TV/Services/APIService.swift MoviePilot-TV/Services/KeychainHelper.swift MoviePilot-TV/ViewModels/SystemViewModel.swift MoviePilot-TV-Tests/CredentialPersistenceTests.swift
```

Expected after commits `082aed9` and `3afbb31`: no save-failure plaintext fallback remains in `APIService`.

- [ ] **Step 3: If the remaining issue is real, write a focused RED test**

Use a fake `CredentialStore` where possible. Do not depend on the tvOS test process being unable to access Keychain, because that can vary by environment.

- [ ] **Step 4: Run only the focused test**

```bash
xcodebuild test \
  -project MoviePilot-TV.xcodeproj \
  -scheme MoviePilot-TV \
  -configuration Debug \
  -destination "platform=tvOS Simulator,name=Apple TV" \
  -only-testing:MoviePilot-TV-Tests/CredentialPersistenceTests \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  -parallel-testing-enabled NO \
  -maximum-concurrent-test-simulator-destinations 1 \
  -skipPackagePluginValidation
```

Expected for a new behavior test before implementation: FAIL for the behavior under test, not a syntax or entitlement error.

- [ ] **Step 5: Implement the minimal fix and rerun the focused test**

Use the same focused `xcodebuild test -only-testing:MoviePilot-TV-Tests/CredentialPersistenceTests` command.

- [ ] **Step 6: Ask a subagent for read-only review**

Prompt shape:

```text
请只读复核本小步，不要修改文件。当前工作区 /private/tmp/MoviePilot-TV-fix-ocr-phase1-safety。目标是 <one-sentence issue>. 已新增/修改测试 <test name>，生产改动在 <files>. 请重点检查测试是否真实覆盖目标行为、是否污染全局状态、生产改动是否过窄或漏掉同一 commit 必须修的问题。中文 findings，按严重程度排列，带文件/行号。
```

- [ ] **Step 7: Run standard verification**

Run dependency resolution, clean build, and full test with the commands from "Current State".

- [ ] **Step 8: Commit the slice**

```bash
git status --short --branch
git diff --cached --stat
git commit -m "[AI] fix/credentials: <specific remaining credential fix>"
```

Only commit after staging the exact files for this slice.

## Task 2: Models Decoding / Avatar Fallback

**Files likely involved:**
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch01-api-service.raw.md`
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch27-person-collection-detail.raw.md`
- Read: `MoviePilot-TV/Models/Models.swift`
- Read: `MoviePilot-TV/Services/APIService.swift`
- Test: existing model/image tests, likely `MoviePilot-TV-Tests/ImageProxyEncodingTests.swift` or a new focused model decoding test file.

- [ ] **Step 1: Verify the OCR claim against current model code**

Look specifically at `Person`, `PersonAvatar`, `BangumiImages`, and any avatar URL building code around `APIService` person image helpers.

- [ ] **Step 2: Compare with existing backend compatibility tests before adding new behavior**

```bash
rg -n "avatar|PersonAvatar|BangumiImages|person" MoviePilot-TV-Tests MoviePilot-TV/Models/Models.swift MoviePilot-TV/Services/APIService.swift
```

- [ ] **Step 3: Write a minimal decoding or URL-building RED test**

The test should use local JSON/data. Do not require a real backend.

- [ ] **Step 4: Implement only the proven fix**

Respect `.agents/ReviewPlan.md`: use `raw_id` when raw backend IDs are required, and do not confuse SwiftUI `id` values with backend IDs.

- [ ] **Step 5: Run focused tests, subagent review, standard verification, and commit**

Suggested commit message:

```text
[AI] fix/models: harden person avatar decoding
```

Use a more specific summary if the verified issue is different.

## Task 3: SubscribeSheet Mistaken Rollback

**Files likely involved:**
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch29-subscribe-sheet.raw.md`
- Read: `MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift`
- Read: `MoviePilot-TV/Views/Sheets/SubscribeSheet.swift`
- Read if frontend comparison is needed: `../MoviePilot-Frontend` subscription dialog files.

- [ ] **Step 1: Verify the OCR finding**

Focus on whether dismissing or failing inside `SubscribeSheet` can incorrectly mark a subscription as not subscribed after a successful operation.

- [ ] **Step 2: Write a RED test at the ViewModel or handler level**

Avoid brittle SwiftUI view tests unless there is already an established pattern. Prefer testing state transitions in `SubscribeSheetViewModel` or a small extracted helper if one already exists.

- [ ] **Step 3: Implement the minimal state fix**

Do not introduce success toasts. `.agents/ReviewPlan.md` says notifications are for user intervention or failures, not success confirmation.

- [ ] **Step 4: Verify and commit**

Suggested commit message:

```text
[AI] fix/subscription: preserve successful subscribe state on dismiss
```

## Task 4: ResourceResultViewModel SSE Lifecycle

**Files likely involved:**
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch32-resource-results.raw.md`
- Read: `MoviePilot-TV/ViewModels/ResourceResultViewModel.swift`
- Read: `MoviePilot-TV/Views/Pages/ResourceResultView.swift`
- Read: `MoviePilot-TV/Views/Components/TorrentsResultView.swift`

- [ ] **Step 1: Verify stale task, cancellation, or SSE error lifecycle issue**

Pay attention to view disappearance, repeated searches, and old SSE events updating new state.

- [ ] **Step 2: Write a RED unit test if the logic can be isolated**

If `ResourceResultViewModel` is too network-coupled, first consider a very small injected API/SSE abstraction. Keep the abstraction local and only if needed by the test.

- [ ] **Step 3: Implement minimal cancellation or generation-token protection**

Do not hide actual errors. Use existing `NotificationManager` only for user-actionable failures.

- [ ] **Step 4: Verify and commit**

Suggested commit message:

```text
[AI] fix/resources: ignore stale resource search updates
```

## Task 5: DownloadTaskViewModel Crash / Stale Request

**Files likely involved:**
- Read: `/private/tmp/MoviePilot-TV-ocr-zero-review-reports/docs/ocr-zero-review/batch35-download-task.raw.md`
- Read: `MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift`
- Read: `MoviePilot-TV/Views/Pages/DownloadTaskView.swift`
- Read models used by download tasks in `MoviePilot-TV/Models/Models.swift`

- [ ] **Step 1: Verify the exact crash or overwrite path**

Look for forced unwraps, unsafe array indexing, stale async fetches, timer/polling lifecycle leaks, and mutation after view disappearance.

- [ ] **Step 2: Write a RED test around the smallest reproducible state transition**

Prefer a test with a fake API response or injected fetch closure. Avoid a real backend.

- [ ] **Step 3: Implement minimal safety**

If the issue is stale response overwrite, use request IDs or task cancellation. If it is a crash on dirty data, harden decoding or indexing at the model/viewmodel boundary.

- [ ] **Step 4: Verify and commit**

Suggested commit message:

```text
[AI] fix/downloads: prevent stale task refresh overwrite
```

## Verification Checklist Before Every Commit

- [ ] Focused test was observed RED for the intended reason.
- [ ] Focused test passed after implementation.
- [ ] A subagent performed read-only review of the slice.
- [ ] Standard dependency resolution passed.
- [ ] Standard clean build passed.
- [ ] Full XCTest passed.
- [ ] `git status --short --branch` shows only intended staged files.
- [ ] Commit message follows `[AI] <type>/<scope>: <summary>`.

## Common Pitfalls

- OCR has false positives. Do not fix a report unless you can explain the concrete bug path.
- Do not rely on Keychain failing in unit tests; use `CredentialStore` injection.
- Do not add broad fallback behavior that MoviePilot Web does not have.
- Do not replace `xcodebuild` validation with `swift build` or `swift test`.
- Do not update `.agents/ReviewPlan.md` as part of implementation commits unless the user asks to archive review progress.
- Do not leave `exec_command` sessions running when ending a turn.
- Do not trust staged content after editing; rerun `git diff --cached` before every commit.
