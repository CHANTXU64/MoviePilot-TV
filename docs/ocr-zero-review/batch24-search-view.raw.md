```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~228687 token(s) used (input: ~223514, output: ~5173), cache(read: ~82432, write: ~0), 2m17s elapsed

─── MoviePilot-TV/Views/Pages/SearchView.swift:162-162 ───
This file currently references several view types that are not defined anywhere under
`MoviePilot-TV` (`TorrentsResultView`, `MultiSelectionSheet`, `ResourceResultView`,
`SubscribeSeasonView`, and `BestResultCard` were not found by search). Unless these are introduced
in another target/module and imported here, the TV target will fail to compile. Please add/port
these components or adjust this view to use the existing TV components.



─── MoviePilot-TV/Views/Pages/SearchView.swift:222-222 ───
The native search bar only binds text to `viewModel.query`; there is no `.onSubmit(of: .search)` or
query observer, and `SearchViewModel` only runs searches when `autoSearch()` is called explicitly.
As a result, typing and pressing Search in the system search UI will not execute any search. Add a
submit handler that calls `autoSearch()` (and consider trimming/empty-query handling there).

        .searchable(text: $viewModel.query, placement: .automatic, prompt: "电影、节目、演职人员等")
+       .onSubmit(of: .search) {
+         Task { await viewModel.autoSearch() }
+       }


─── MoviePilot-TV/Views/Pages/SearchView.swift:217-217 ───
Changing the selected sites only updates the binding; neither this view nor `SiteFilterViewModel`
reruns the resource search after the sheet is dismissed/selection changes. If the user has already
searched in resource mode, the displayed results remain for the old site set while the button label
shows the new filter. Trigger `autoSearch()` when the sheet closes or when `selectedSites` changes
while in resource mode.

```
