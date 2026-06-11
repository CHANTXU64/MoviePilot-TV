```text
[ocr] Summary: 2 file(s) reviewed, 5 comment(s), ~500493 token(s) used (input: ~490652, output: ~9841), cache(read: ~220672, write: ~0), 4m33s elapsed

─── MoviePilot-TV/ViewModels/MediaActionHandler.swift:13-13 ───
When `apiMediaId` is unavailable this builds a resource search with an empty `keyword`.
`APIService.searchResources` treats non-ID keywords as `/search/title` and the tvOS implementation
does not implement the Vue empty-keyword `/search/last` fallback, so this can issue an empty title
search instead of searching the media title. Consider falling back to
`title`/`original_title`/`original_name` or avoiding navigation when no searchable key exists.

-      keyword: item.apiMediaId ?? "",
+      keyword: item.apiMediaId ?? item.title ?? item.original_title ?? item.original_name ?? "",


─── MoviePilot-TV/ViewModels/MediaActionHandler.swift:35-41 ───
`isRecognizingTmdb` is a single shared flag around an awaited call. If two jump-target resolutions
run at the same time, the first one to finish will set the flag to `false` while the second
recognition is still in flight, so the UI can hide the loading state prematurely. Use a per-request
state or an in-flight counter (and reset via cleanup) so the published state reflects all active
recognitions.



─── MoviePilot-TV/ViewModels/MediaActionHandler.swift:75-75 ───
Preserving `collection_id` can accidentally mark this partial TMDB jump target as a collection,
because `MediaInfo.checkIsCollection` returns true whenever `collection_id != nil`.
`MediaPreloader.start()` skips detail loading for collection items, so a movie/TV target that only
carries a stale collection id may never fetch its TMDB detail. Clear this field for media-detail
jump targets unless the target is intentionally a collection.

-      collection_id: item.collection_id,
+      collection_id: nil,


─── MoviePilot-TV/ViewModels/SubscriptionHandler.swift:32-32 ───
The TMDB ID found from `MediaPreloader` is only used for the duplicate-check fallback, but the
`Subscribe` object opened in the editor is still built from the original `item`. For Douban/Bangumi
media where `item.tmdb_id` is nil, the resulting request keeps `tmdbid` nil even after a valid TMDB
match was found, so the backend may create/match the subscription under a different media identity
than the duplicate check used. Consider carrying the fallback TMDB ID into
`mediaInfoToSubscribeRequest`.

-          self.sheetSubscribe = mediaInfoToSubscribeRequest(item)
+          self.sheetSubscribe = mediaInfoToSubscribeRequest(item, tmdbIdOverride: fallbackTmdbId)


─── MoviePilot-TV/ViewModels/SubscriptionHandler.swift:8-8 ───
This published state is never read or written anywhere in the current project changes
(`forkSheetRequest` only appears here). Keeping unused UI state makes the view model harder to
reason about and may indicate that the fork-subscription sheet flow is incomplete. Remove it unless
an external view binding is intended to be added in this batch.
```
