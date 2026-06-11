```text
[ocr] Summary: 3 file(s) reviewed, 8 comment(s), ~352661 token(s) used (input: ~340826, output: ~11835), cache(read: ~131584, write: ~0), 5m18s elapsed

─── MoviePilot-TV/Services/CustomFilterService.swift:30-31 ───
`SystemViewModel` is not defined anywhere in the current project, and these two accessors have no
other references, so this new service will fail to compile. Either add the missing selection
accessors/model in this change or read the selected filter rule IDs from an existing persisted
configuration source.



─── MoviePilot-TV/Services/CustomFilterService.swift:52-53 ───
Matched items keep their previous `isFilteredOut` value. Because `Context` carries this UI state and
filtered results may be reused across refreshes or rule changes, an item that was previously
unmatched can remain greyed out even after it matches the new soft rule. Reset the flag for both
branches when applying a soft filter.

         if matchRule(context: ctx, rule: softRule) {
+          ctx.isFilteredOut = false
           matched.append(ctx)


─── MoviePilot-TV/Services/CustomFilterService.swift:161-167 ───
`CustomRule.size_range` is documented in the model as supporting a single `"min"` value, but this
implementation only accepts `min-max`, `>min`, and `<max`. A valid single-value size rule therefore
falls through and excludes every resource. Add handling for a plain numeric value, or align the
model/API contract with the accepted formats.

     } else if trimmed.hasPrefix("<") {
       let valueStr = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
       guard let maxMB = Double(valueStr) else { return false }
       if perEpisodeSize <= maxMB * 1024 * 1024 {
+        return true
+      }
+    } else if let minMB = Double(trimmed) {
+      if perEpisodeSize >= minMB * 1024 * 1024 {
         return true
       }
     }


─── MoviePilot-TV/Services/CustomFilterService.swift:107-113 ───
The `CustomRule.seeders` model allows `"min"` or `"min-max"`, but `Int(seedersStr)` fails for a
range such as `"10-50"`; in that case the whole seeders filter is silently skipped. Parse the range
explicitly (or reject invalid formats consistently) so configured seeder bounds are actually
enforced.



─── MoviePilot-TV/Services/Paginator.swift:89-93 ───
Because `threshold` is a public initializer input, a value of `0` or a negative value breaks the
`loadMore(currentItemId:)` boundary check (`items.count - threshold` can become `items.count` or
larger, so no item can satisfy it). A non-positive `prefetchThreshold` also disables/distorts
prefetch batching. Consider normalizing or rejecting these values at initialization so callers
cannot accidentally create a paginator that never loads more from scrolling.

-    self.threshold = threshold
+    self.threshold = max(1, threshold)
     self.fetcher = fetcher
     self.processor = processor
     self.imageURLsProvider = imageURLsProvider
-    self.prefetchThreshold = prefetchThreshold ?? ((threshold + 1) / 2)
+    self.prefetchThreshold = max(1, prefetchThreshold ?? ((max(1, threshold) + 1) / 2))


─── MoviePilot-TV/Services/Paginator.swift:288-290 ───
This marks pagination as exhausted after two pages that contain only already-known items, even
though the backend may still have later pages with unique content (for example, APIs with overlap,
unstable sorting, or items filtered out by `processor`). Since `page` has already advanced, consider
leaving `hasMore` true when the scan limit is reached without an empty page, or make this
limit/configuration explicit so valid later content is not hidden.

     if !hasNewContent && currentError == nil {
-      hasMore = false
+      // Keep hasMore unchanged unless an empty page explicitly set it to false above.
+      // This allows a later loadMore call to continue from the advanced page cursor.
     } else if let error = currentError {


─── MoviePilot-TV/Services/ParsedSeason.swift:122-123 ───
`sortSeasonOptions` currently places every whole-season option before every episode option after
sorting each group separately. For a mixed list like `["S03E10", "S01"]`, this returns `S01` before
the newer S03 episode, which conflicts with the stated descending “latest season/episode first”
behavior and can surface outdated options ahead of newer ones. Consider using one global comparator
by season/episode, with `isWholeSeason` only as a tie-breaker within the same season if whole-season
entries should be preferred there.



─── MoviePilot-TV/Services/ParsedSeason.swift:36-40 ───
The regex accepts season ranges such as `S01-S02`, but the second captured season number is never
read. Those entries are treated as season 1 only, so `S01-S02` sorts below `S02` even though the
option includes season 2. If range values are valid backend options, store the ending season (or
normalized max season) and use it in the sort key.
```
