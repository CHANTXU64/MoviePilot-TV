```text
[ocr] Summary: 2 file(s) reviewed, 7 comment(s), ~273626 token(s) used (input: ~265250, output: ~8376), cache(read: ~94720, write: ~0), 8m35s elapsed

─── MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:32-32 ───
`Dictionary(uniqueKeysWithValues:)` will fatal-error if `downloads` ever contains duplicate ids.
This can happen if a previous API response contains duplicates: the first load inserts all
`newItems`, and the next poll crashes while building this dictionary. Use a non-trapping
construction and consider de-duplicating incoming items before reconciling.

-       let existingDownloadsById = Dictionary(uniqueKeysWithValues: downloads.map { ($0.id, $0) })
+       let existingDownloadsById = Dictionary(downloads.map { ($0.id, $0) }, uniquingKeysWith: { existing, _ in existing })


─── MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:30-30 ───
Because `selectedClient` is read before the `await` and the result is applied after it, a slower
request for a previously selected client can overwrite the downloads for the currently selected
client. This is possible because the view triggers `loadDownloads()` from both the picker `onChange`
and the polling task. Capture the requested client and verify it is still selected before mutating
`downloads`.

-       let newDownloads = try await apiService.fetchDownloading(clientName: selectedClient)
+       let clientName = selectedClient
+       let newDownloads = try await apiService.fetchDownloading(clientName: clientName)
+       guard selectedClient == clientName else { return }


─── MoviePilot-TV/ViewModels/DownloadTaskViewModel.swift:88-89 ───
The same stale-client race can remove an item from the currently displayed list after the user
switches clients while the delete request is in flight. Capture the client used for the request and
only mutate `downloads` if it is still the selected client when the response returns.

+       let clientName = selectedClient
        let (success, message) = try await apiService.deleteDownload(
-         clientName: selectedClient, hash: hash)
+         clientName: clientName, hash: hash)
+       guard selectedClient == clientName else { return }


─── MoviePilot-TV/Views/Pages/DownloadTaskView.swift:27-29 ───
This starts an independent load whenever the selected client changes while the `.task` polling loop
below can also have an in-flight `loadDownloads()`. Since `loadDownloads()` applies its result after
the await without checking whether the selected client/request is still current, an older response
can overwrite the list for a newer client and cause flicker or incorrect tasks to be shown. Consider
cancelling/serializing refreshes, or moving request-token/client validation into the view model
before publishing results.

            .onChange(of: viewModel.selectedClient) { _, _ in
              Task { await viewModel.loadDownloads() }
            }


─── MoviePilot-TV/Views/Pages/DownloadTaskView.swift:79-79 ───
The button state only treats the exact string `downloading` as active, while `DownloadingInfo.state`
is decoded directly from the backend/client. Download clients commonly expose active states such as
`stalledDL`, `queuedDL`, `forcedDL`, `metaDL`, etc.; those would be shown as “继续” and call
`startDownload` even though the task is already active. Consider centralizing an
`isActiveDownloadState` helper that covers all non-paused/error terminal states, and reuse it here
and in `onChange`.

-     _isDownloading = State(initialValue: item.state?.lowercased() == "downloading")
+     _isDownloading = State(initialValue: Self.isActiveDownloadState(item.state))


─── MoviePilot-TV/Views/Pages/DownloadTaskView.swift:96-99 ───
A successful API response here only means the command was accepted; it does not include the task's
new state. Toggling the local flag can show the opposite action even if the task transitions to
`queued`, `stalled`, `checking`, or errors on the backend, and the UI remains inconsistent until the
next poll. Prefer reloading the task state after a successful command, or derive this button solely
from `item.state` once the refresh returns.

-       // API 调用成功，则翻转 UI 状态
        if operationSuccess {
-         isDownloading.toggle()
+         await viewModel.loadDownloads()
        }


─── MoviePilot-TV/Views/Pages/DownloadTaskView.swift:56-60 ───
`initialLoad()` already calls `loadDownloads()`, so the first loop iteration immediately fetches the
same list again before sleeping. That doubles the initial network/update work every time the view
appears. Consider sleeping before the next refresh, or make `initialLoad()` only fetch clients and
let the loop perform the first download load.

      await viewModel.initialLoad()
      while !Task.isCancelled {
-         await viewModel.loadDownloads()
        try? await Task.sleep(nanoseconds: 3 * 1_000_000_000)  // 3 seconds
+         guard !Task.isCancelled else { break }
+         await viewModel.loadDownloads()
      }
```
