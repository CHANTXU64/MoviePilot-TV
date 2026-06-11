```text
[ocr] Summary: 1 file(s) reviewed, 4 comment(s), ~109688 token(s) used (input: ~105183, output: ~4505), cache(read: ~38912, write: ~0), 2m14s elapsed

─── MoviePilot-TV/ViewModels/HomeViewModel.swift:182-182 ───
`Subscribe.state` supports more than just `R` and `S` (`N`, `R`, `P`, `S` in the model). With the
current ternary, calling this for a new/pending/unknown subscription will send `S` and overwrite its
state as paused. Consider only toggling known running/paused states and returning `false` or
surfacing an error for unsupported/nil states.

-    let newState = subscribe.state == "S" ? "R" : "S"
+    let newState: String
+    switch subscribe.state {
+    case "S":
+      newState = "R"
+    case "R":
+      newState = "S"
+    default:
+      return false
+    }


─── MoviePilot-TV/ViewModels/HomeViewModel.swift:53-54 ───
`hasLoaded` is set before the initial refresh actually succeeds, while `refreshData()`/its loaders
swallow errors. If the first network/auth request fails, later `loadData()` calls will be ignored
and the home screen can remain empty until some separate refresh path is triggered. Consider setting
this flag only after a successful initial load, or resetting it when the initial load produced no
usable data / exposing retry state.

     guard !hasLoaded else { return }
-    hasLoaded = true


─── MoviePilot-TV/ViewModels/HomeViewModel.swift:73-74 ───
This view model is `@MainActor`, but `withTaskGroup` child closures are `@Sendable` and run outside
the actor. Capturing `self` here (and again inside `loadLatestMedia`'s nested task group via
`self.apiService`) can trigger Swift concurrency isolation/Sendable diagnostics because `APIService`
is a mutable `ObservableObject`, and it may also serialize parts of the work back through the main
actor. Prefer capturing a thread-safe service outside the group or moving the concurrent fetching
into a non-main-actor/service layer that is explicitly safe to call concurrently.



─── MoviePilot-TV/ViewModels/HomeViewModel.swift:226-230 ───
After deleting, this method reloads subscriptions and then posts `.subscriptionDidUpdate`; this same
`HomeViewModel` subscribes to that notification and calls `loadSubscriptions()` again, so a local
delete causes two subscription fetches. Consider posting first and letting the notification path
refresh, or ignore self-originated notifications / skip the local reload.

       if success {
-        await loadSubscriptions()
-        // 通知其他页面（如详情页 preloadTask）订阅已变更
+        // 通知其他页面（如详情页 preloadTask）订阅已变更；本 ViewModel 的监听也会刷新订阅列表
         NotificationCenter.default.post(name: .subscriptionDidUpdate, object: nil)
       }
```
