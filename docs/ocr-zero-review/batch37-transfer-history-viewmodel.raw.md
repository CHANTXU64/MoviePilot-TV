```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~127760 token(s) used (input: ~124208, output: ~3552), cache(read: ~45056, write: ~0), 3m49s elapsed

─── MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:108-113 ───
This closure is stored by the view model itself and captures `self` strongly via `self.pageSize`,
creating a retain cycle after `search(with:)` is called. The initializer already avoids this pattern
by copying `pageSize` into a local constant; do the same here (or capture weakly) so the view model,
paginator subscriptions, and tasks can be released when the screen is dismissed.

+     let pageSize = self.pageSize
      self.fetcher = { page in
        try await api.fetchTransferHistory(
          page: page,
-         count: self.pageSize,
+         count: pageSize,
          title: title)
      }


─── MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:226-228 ───
Batch deletion swallows per-item failures unless every deletion fails, so a partial failure leaves
the user with no error indication while failed IDs remain selected. Track failed IDs/errors and set
a user-visible `errorMessage` when any item fails, while keeping failed rows selected if you want
retry behavior.

        } catch {
          print("Failed to delete history item \(id): \(error.localizedDescription)")
+           errorMessage = "部分项目删除失败，请检查后端日志。"
        }


─── MoviePilot-TV/ViewModels/TransferHistoryViewModel.swift:429-430 ───
Cancelling the previous AI redo task can leave its IDs stuck in `aiRedoingIds`: the cancelled task
skips cleanup because the cleanup paths are guarded by `!Task.isCancelled`. If the user starts
another redo while one is running, old rows can remain permanently marked as processing and
`isAiRedoing` can become inconsistent. Add cancellation cleanup for the previous task's pending IDs
(for example with `defer` inside the task or by explicitly removing the previous IDs before
replacing the task).

```
