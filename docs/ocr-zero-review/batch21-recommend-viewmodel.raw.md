```text
[ocr] Summary: 1 file(s) reviewed, 1 comment(s), ~212840 token(s) used (input: ~206753, output: ~6087), cache(read: ~88576, write: ~0), 3m18s elapsed

─── MoviePilot-TV/ViewModels/RecommendViewModel.swift:142-144 ───
The initial refresh is launched as an untracked task. When the user switches shelves/categories or
the view model is released, this outer task can keep the old `Paginator` alive until the request
finishes, so stale network work may continue even after `paginator?.cancel()` has been called.
Consider storing the refresh task and cancelling it together with the old paginator (and in
`deinit`) before starting a new refresh.

-     Task {
+     refreshTask?.cancel()
+     refreshTask = Task {
        await newPaginator.refresh()
      }
```
