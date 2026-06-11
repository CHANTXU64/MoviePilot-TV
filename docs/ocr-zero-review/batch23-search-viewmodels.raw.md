```text
[ocr] Summary: 2 file(s) reviewed, 6 comment(s), ~356352 token(s) used (input: ~349489, output: ~6863), cache(read: ~141312, write: ~0), 3m25s elapsed

─── MoviePilot-TV/ViewModels/SearchViewModel.swift:240-241 ───
Unified searches are not protected against overlapping `autoSearch()` calls. A later search
recreates `submittedQuery`/paginators while an earlier unified search is still awaiting its refresh
tasks; when the earlier call resumes it can calculate `bestResults` using stale paginator items but
the newer `submittedQuery`, then overwrite the newer loading/search state. Consider adding a search
generation token or a separate unified-search task that is cancelled/validated before committing
results.

    private var searchStreamTask: Task<Void, Never>?
+   private var searchGeneration: Int = 0
    private let searchStreamDoneCloseDelay: UInt64 = 1_500_000_000


─── MoviePilot-TV/ViewModels/SearchViewModel.swift:135-137 ───
`maxS` can be `-1` when none of the candidate titles match the query, but this still appends any
item that has a poster or enough popularity. That can put unrelated entries into the “best results”
section. Apply a minimum match threshold independently of poster/popularity before adding the item.

-       if !(hasNoPoster && maxS < 50 && pop < 1) {
+       if maxS >= 0, !(hasNoPoster && maxS < 50 && pop < 1) {
          scoredItems.append((item: .media(mediaItem), score: maxS, popularity: pop))
        }


─── MoviePilot-TV/ViewModels/SearchViewModel.swift:301-304 ───
The resource-search task captures `self` strongly and there is no lifecycle cancellation (for
example in `deinit`). If the SSE stream hangs or the view model is discarded, the task can retain
the view model and continue network work/state updates. Add explicit cancellation on deinit or avoid
the strong retention cycle.

                let filteredResults = await self.applyCustomFilter(to: accumulatedResults)
                self.resourceResults = filteredResults
                self.isLoading = false
                self.hasSearched = true


─── MoviePilot-TV/ViewModels/SearchViewModel.swift:446-449 ───
This only deduplicates against previously appended people. If `newItems` itself contains duplicate
`raw_id` values, all duplicates pass because `existingIds` is not updated while filtering. Use a
mutable `seenIds` set (or `Person.id`) and insert as each new item is accepted.

-         let existingIds = Set(currentItems.compactMap { $0.raw_id })
-         let uniqueNewItems = newItems.filter {
-           $0.raw_id == nil || !existingIds.contains($0.raw_id!)
+         var seenIds = Set(currentItems.compactMap { $0.raw_id })
+         let uniqueNewItems = newItems.filter { item in
+           guard let rawId = item.raw_id else { return true }
+           return seenIds.insert(rawId).inserted
          }


─── MoviePilot-TV/ViewModels/SearchViewModel.swift:0-0 ───
Whitespace-only or leading/trailing-space input still triggers network searches and also weakens
local best-result matching because `submittedQuery` keeps the extra spaces. Normalize the query once
before searching and skip if the trimmed value is empty.

-     guard !query.isEmpty else { return }
+     let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
+     guard !normalizedQuery.isEmpty else { return }
      
      searchStreamTask?.cancel()
      
      isLoading = true
      hasSearched = false
-     submittedQuery = query
+     submittedQuery = normalizedQuery


─── MoviePilot-TV/ViewModels/SiteFilterViewModel.swift:35-37 ───
`sitesString` can expose the raw default site IDs before `loadSites()` has completed (or if loading
sites fails). In that case `normalizeSelectedSites()` is never applied, so resource search may send
IDs for deleted/unavailable sites; this is exactly what the existing
`SystemViewModel.normalizedDefaultSearchSitesString()` path tries to avoid. Consider tracking
whether site data has been loaded and only returning IDs after normalization, or make callers await
a normalization step before using this value.

    var sitesString: String? {
-     selectedSites.isEmpty ? nil : selectedSites.sorted().map { String($0) }.joined(separator: ",")
+     guard availableSites.isEmpty == false else { return nil }
+     let availableSiteIds = Set(availableSites.map(\.id))
+     let normalizedSites = selectedSites.intersection(availableSiteIds)
+     return normalizedSites.isEmpty ? nil : normalizedSites.sorted().map { String($0) }.joined(separator: ",")
    }
```
