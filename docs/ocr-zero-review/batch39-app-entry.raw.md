```text
[ocr] Summary: 1 file(s) reviewed, 1 comment(s), ~356303 token(s) used (input: ~349697, output: ~6606), cache(read: ~156672, write: ~0), 5m31s elapsed

─── MoviePilot-TV/Views/ContentView.swift:51-60 ───
The debounced validation task is only cancelled by a later tab change. If the user logs out
(switching this branch to `LoginView`) or the app moves to background before the 5-second sleep
completes, the task can still wake up and run validation for a view state that is no longer active.
Please cancel the pending task when the authenticated tab view disappears (and optionally when the
scene becomes inactive/background) to avoid stale background work.

        .onChange(of: selectedTab) { _, _ in
          // 防抖逻辑：取消之前的任务，重新计时
          checkTask?.cancel()
          checkTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)  // 5 秒
            if !Task.isCancelled {
              APIService.shared.validateTokenSilently()
+             }
            }
          }
+         .onDisappear {
+           checkTask?.cancel()
+           checkTask = nil
        }
```
