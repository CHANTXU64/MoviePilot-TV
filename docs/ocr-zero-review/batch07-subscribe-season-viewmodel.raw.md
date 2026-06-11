```text
[ocr] Summary: 1 file(s) reviewed, 5 comment(s), ~163051 token(s) used (input: ~158415, output: ~4636), cache(read: ~64512, write: ~0), 2m10s elapsed

─── MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift:162-166 ───
Because this view model is `@MainActor`, the `group.addTask` body runs outside the main actor and
cannot safely read `self.mediaInfo`. With stricter Swift concurrency checking this can fail to
compile (or at least produce actor-isolation diagnostics). Capture the needed value before creating
child tasks and use that local value inside the task instead of touching `self` from the task body.

+        let mediaInfo = mediaInfo
         group.addTask {
           do {
             // 遍历所有季并检查订阅状态，失败则静默跳过
             let isSubscribed = try await APIService.shared.checkSubscription(
-              media: self.mediaInfo, season: seasonNumber)
+              media: mediaInfo, season: seasonNumber)


─── MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift:165-166 ───
This check ignores the selected episode group, while `prepareSubscription` creates grouped
subscriptions with `episode_group`. The subscription API key is only media id + season, so after
switching to an episode group the UI may report the grouped subscription as not subscribed (or match
a standard-season subscription instead). Build and pass a `MediaInfo` that carries `selectedGroupId`
consistently, or extend the API call to include `episode_group`.

             let isSubscribed = try await APIService.shared.checkSubscription(
-              media: self.mediaInfo, season: seasonNumber)
+              media: checkMedia, season: seasonNumber)


─── MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift:214-215 ───
Cancellation has the same grouped-season mismatch: grouped subscriptions are created with
`episode_group`, but deletion is performed with the original `mediaInfo` and only the season number.
For media with multiple episode-group mappings, this can fail to delete the intended subscription or
delete the wrong season entry. Pass the selected episode group through the delete request path as
well.



─── MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift:34-36 ───
`hasLoaded` is set before any network request succeeds. If fetching episode groups or seasons fails
once, later `loadData` calls immediately return and the user cannot retry with the same view model.
Set this flag after `fetchSeasonsInternal` succeeds, or reset it in the `catch` block.

-    hasLoaded = true
     isLoading = true
     defer { isLoading = false }


─── MoviePilot-TV/ViewModels/SubscribeSeasonViewModel.swift:150-152 ───
On status-check failure this leaves the previous `seasonsNotExisted` values intact. After switching
episode groups, stale statuses from the prior group can keep showing incorrect availability labels
and can also make `prepareSubscription` choose the wrong `best_version`. Clear the status map or
surface the error before returning.

     } catch {
-      print("检查季入库状态失败: \(error)")
+      seasonsNotExisted = [:]
+      errorMessage = error.localizedDescription
     }
```
