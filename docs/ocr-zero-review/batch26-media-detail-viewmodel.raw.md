```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~155052 token(s) used (input: ~150181, output: ~4871), cache(read: ~59904, write: ~0), 4m11s elapsed

─── MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:295-308 ───
`withTaskGroup.addTask` runs its closures outside the `@MainActor` isolation of this view model, but
these closures capture `self` to access `apiService` and `preloadTask`. Under stricter Swift
concurrency this can fail to compile, and without it the code risks reading/mutating UI-owned state
from a non-main child task. Snapshot the values needed on the main actor before adding tasks, avoid
capturing `self` inside the task body except for a final `MainActor.run`/weak update, or make the
called service actor/thread-safe explicitly.



─── MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:168-172 ───
This unstructured task is not retained or cancelled and it strongly captures the view model through
the paginator/property accesses. If the detail screen is dismissed while these requests are running,
the task can keep the view model alive and still publish results later. Store this task in a
property and cancel it from `deinit`/when applying a new detail, or capture `self` weakly and exit
when the view model is gone.



─── MoviePilot-TV/ViewModels/MediaDetailViewModel.swift:274-274 ───
`try?` discards deletion failures, but the method still refreshes state and posts
`subscriptionDidUpdate` as if cancellation succeeded. A backend/network failure will be invisible to
callers and can trigger misleading UI updates. Handle the thrown error explicitly (for example by
exposing an error state/toast and returning before posting the success notification).

```
