```text
[ocr] Summary: 3 file(s) reviewed, 5 comment(s), ~275316 token(s) used (input: ~265895, output: ~9421), cache(read: ~115712, write: ~0), 5m13s elapsed

─── MoviePilot-TV/ViewModels/ContentViewModel.swift:49-49 ───
`MediaPreloader` is not defined anywhere in the current project, so this new view model will fail to
compile as soon as it is included in the target. Either add the preloader implementation to this
batch/target, or guard this call behind an existing cache-clearing API.



─── MoviePilot-TV/ViewModels/ContentViewModel.swift:39-44 ───
Because `@Published` publishers emit their current value to new subscribers, the `$token`
subscription above already schedules `fetchSettings()` when a persisted token exists at cold start.
This extra initial `if isLoggedIn` block therefore sends a second concurrent settings request on
launch. Consider relying on the subscription’s initial emission, or de-duplicating through a single
refresh method/task.

-    // 如果已经登录则进行初始获取（例如：应用带有效令牌冷启动）
-    if isLoggedIn {
-      Task { [weak self] in
-        try? await self?.apiService.fetchSettings()
-      }
-    }
+    // The $token subscription emits the persisted token on subscription, so it also covers
+    // the cold-start settings fetch when already logged in.


─── MoviePilot-TV/ViewModels/LoginViewModel.swift:25-25 ───
`serverURL` is assigned to the shared `APIService` before any validation, and `APIService.baseURL`
persists immediately to `UserDefaults`. If the field is empty/whitespace or includes a malformed
value, a failed login can still overwrite the previously working server address and leave later
token validation/auto-login calls pointing at an invalid URL. Consider trimming/validating the URL
before mutating the shared service, and only persisting it once it passes basic checks (or after
login succeeds).

-apiService.baseURL = serverURL
+    let normalizedURL = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
+    guard let url = URL(string: normalizedURL), url.scheme != nil, url.host != nil else {
+      isLoading = false
+      errorMessage = "服务器地址无效"
+      return false
+    }
+ 
+    apiService.baseURL = normalizedURL
+ 
+    do {


─── MoviePilot-TV/ViewModels/NotificationManager.swift:54-60 ───
`task` is retained by `self.task`, and this work item’s closure captures `self` strongly. Because
`self.task` is never cleared after the dismissal runs, the manager can form a retain cycle and keep
the view model/UI state alive longer than intended. Capture `self` weakly and clear the stored task
after the hide completes.

-      let task = DispatchWorkItem {
+      let task = DispatchWorkItem { [weak self] in
+        guard let self else { return }
         withAnimation(.spring()) {
           self.isShowing = false
         }
+        self.task = nil
       }
       self.task = task
       DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: task)


─── MoviePilot-TV/ViewModels/NotificationManager.swift:37-40 ───
This `ObservableObject` owns `@Published` UI state, but the type itself is not main-actor isolated.
`show` currently hops to `DispatchQueue.main`, yet the compiler cannot enforce that future state
access/mutations stay on the UI actor, which can lead to Swift concurrency warnings or accidental
off-main updates. Consider annotating the manager as `@MainActor` and using structured
concurrency/main-actor isolation instead of relying only on manual dispatching.
```
