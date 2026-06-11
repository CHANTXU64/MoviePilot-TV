```text
[ocr] Summary: 3 file(s) reviewed, 8 comment(s), ~437252 token(s) used (input: ~426158, output: ~11094), cache(read: ~162304, write: ~0), 11m56s elapsed

─── MoviePilot-TV/ViewModels/ResourceResultViewModel.swift:57-58 ───
This condition is broader than the non-streaming `searchResources` routing (`^[a-zA-Z]+:`). Any
normal title that starts with letters and contains a colon later (for example `Movie: Part 2`) will
be sent to `/search/media/.../stream` instead of title search, while the fallback path would route
it differently. Consider using the same anchored regex as `searchResources` so streaming and
fallback behavior stay consistent.

-         if keyword.contains(":") && keyword.prefix(while: { $0.isLetter }).count > 0 {
+         if keyword.range(of: "^[a-zA-Z]+:", options: .regularExpression) != nil {
            stream = APIService.shared.searchMediaStream(


─── MoviePilot-TV/ViewModels/ResourceResultViewModel.swift:89-92 ───
An application-level stream error is only logged and then treated like a completed stream: execution
continues into missing-site retry/filtering and finally clears `isLoading`. If the backend emits
`type == "error"` without throwing, the non-streaming fallback in the `catch` block is skipped and
the UI can show partial/empty results as a successful search. Consider throwing/setting an error
flag here and routing through the fallback path, or publish an explicit error state.



─── MoviePilot-TV/ViewModels/ResourceResultViewModel.swift:41-43 ───
`hasSearched` is set before any request succeeds and is never reset on stream/fallback failure.
After a transient network/API failure, any later call to `search()` returns immediately, so the same
view model cannot retry even though `isLoading` has been cleared. Consider only marking the search
as completed after success, or resetting it when both stream and fallback fail/cancel.



─── MoviePilot-TV/ViewModels/ResourceResultViewModel.swift:50-51 ───
This task captures `self` strongly and there is no cancellation hook (`deinit`/`cancel()` called
from the view on disappear). If the SSE stream stalls or the view is dismissed with the “取消” button,
the network task can keep running and retain the view model until the stream ends. Consider exposing
a `cancelSearch()` and calling it from `onDisappear`, and/or cancelling `searchStreamTask` in
`deinit`.



─── MoviePilot-TV/Views/Components/TorrentsResultView.swift:110-113 ───
The view only refreshes its cached `filterOptions` and `filteredResults` when the ID list changes.
Because `filteredResults` stores copies of `Context`, updates to torrent metadata with stable IDs
(for example seeders/peers, size, site, promotion factor, or parsed metadata) will not update the
rendered cards, filter choices, counts, or sort order. Consider recomputing from a change token that
includes the fields used for display/filter/sort, or avoiding this extra state and deriving the
filtered results from `result`, `filterForm`, and sort state.



─── MoviePilot-TV/Views/Components/TorrentsResultView.swift:275-278 ───
Sorting publication time by the raw `pubdate` string is only correct if every backend value is in a
lexicographically sortable format. Other code parses `pubdate` with SwiftDate before comparing it,
so mixed/common date formats can be ordered incorrectly here. Parse to a date (using the same
helper/SwiftDate path as `toRelativeDateString` / `CustomFilterService`) and then compare dates,
with a defined fallback for unparseable values.



─── MoviePilot-TV/Views/Components/TorrentsResultView.swift:298-300 ───
This labels every non-free discount below 1.0 as `50%`. Since the model stores
`downloadvolumefactor` as a `Double` and also exposes the backend `volume_factor` text, values such
as 25%, 30%, or 75% would be grouped and displayed as the wrong promotion filter. Consider deriving
the label from `volume_factor` when present, or formatting `dl` as `Int(dl * 100)%`.



─── MoviePilot-TV/Views/Pages/ResourceResultView.swift:73-75 ───
`search()` starts its own `searchStreamTask` and returns immediately, so the SwiftUI `.task` created
here does not actually own the lifetime of the network search. When this view is dismissed or
recreated, SwiftUI can cancel only this wrapper task, while the stream task keeps running and
continues to hold/update the view model. Please tie the spawned task to the view lifecycle, e.g.
expose/call a `cancelSearch()` from `onDisappear`/the cancel button, or make `search()` await the
stream work directly so `.task` cancellation propagates.

    .task {
      await viewModel.search()
+     }
+     .onDisappear {
+       viewModel.cancelSearch()
    }

```
