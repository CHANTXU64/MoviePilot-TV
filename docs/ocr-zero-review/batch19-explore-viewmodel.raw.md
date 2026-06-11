```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~405892 token(s) used (input: ~399149, output: ~6743), cache(read: ~169472, write: ~0), 3m35s elapsed

─── MoviePilot-TV/ViewModels/ExploreViewModel.swift:467-470 ───
For the subscription-share source these items have already been converted from `SubscribeShare` to
`MediaInfo`, but `MediaInfo.id` is generated only from media identifiers such as
tmdb/douban/type/season and does not include the share id. As a result, multiple share rules for the
same title—or shares without tmdb/douban ids—will be collapsed by this deduplication and disappear
from the list. Please use the embedded `subscribeShare.id` as the dedupe key for
`.subscriptionShare`, or keep a separate `Paginator<SubscribeShare>` for that source.

-        let uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
+        let uniqueNewItems: [MediaInfo]
+        if source == .subscriptionShare {
+          uniqueNewItems = newItems.filter { item in
+            let key = item.subscribeShare?.id ?? item.id
+            guard !seenKeys.contains(key) else { return false }
+            seenKeys.insert(key)
+            return true
+          }
+        } else {
+          uniqueNewItems = MediaInfo.deduplicate(newItems, existingKeys: &seenKeys)
+        }
         if uniqueNewItems.isEmpty {
           return false
         }


─── MoviePilot-TV/ViewModels/ExploreViewModel.swift:411-417 ───
These query parameters are interpolated into the raw path before `APIService.buildEndpoint` parses
it with `URLComponents`. If a filter value ever contains reserved characters such as `&`, `=`, `+`,
or `#` (the properties are public `@Published` strings), the value can be split into extra query
parameters or make the URL invalid before `URLQueryItem` gets a chance to encode it. Building the
query via `URLQueryItem`/`URLComponents` here, or percent-encoding every value with a
query-value-safe character set, would make this robust and consistent with `page` handling in
`APIService`.



─── MoviePilot-TV/ViewModels/ExploreViewModel.swift:429-435 ───
Same raw-query construction issue here: `stype` and the other filter values are inserted directly
into the path string. Please construct these as `URLQueryItem`s (or otherwise encode values before
concatenation) so localized values and any future non-dictionary filter values cannot break backend
parsing.
```
