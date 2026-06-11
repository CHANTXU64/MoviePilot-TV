```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~252080 token(s) used (input: ~243276, output: ~8804), cache(read: ~105472, write: ~0), 3m48s elapsed

─── MoviePilot-TV/ViewModels/MediaPreloader.swift:375-377 ───
When the cache grows past `maxCacheSize` because all old entries are pinned, unpinning later does
not trigger eviction, so the cache can remain oversized indefinitely until another `preload(for:)`
call happens. On tvOS this can retain completed details/season view models longer than the LRU limit
intends. Consider evicting immediately after removing the pin.

   func unpin(key: String) {
     pinnedKeys.remove(key)
+    evictIfNeeded()
   }


─── MoviePilot-TV/ViewModels/MediaPreloader.swift:159-161 ───
There is a cancellation race here: if the Swift task is cancelled before `activeImageDownload` is
assigned, `onCancel` sees `nil` and resumes the continuation, but this closure can still start and
store a Kingfisher request afterward. That leaves an HTTP image download running after LRU
eviction/clearAll cancellation. Add a cancellation check before starting the request and cancel the
returned task if cancellation arrives during `retrieveImage`.

         continuationBox.set(continuation)
+        guard !Task.isCancelled else { return }
         let modifier = AnyModifier.cookieModifier
-        self.activeImageDownload = KingfisherManager.shared.retrieveImage(
+        let downloadTask = KingfisherManager.shared.retrieveImage(
+          with: .network(url),
+          options: [.requestModifier(modifier), .cacheOriginalImage]
+        ) { _ in
+          continuationBox.resume()
+        }
+        self.activeImageDownload = downloadTask
+        if Task.isCancelled {
+          downloadTask?.cancel()
+          continuationBox.resume()
+        }


─── MoviePilot-TV/ViewModels/MediaPreloader.swift:46-46 ───
This only skips items with a non-nil `collection_id`, but `MediaInfo.isCollection` also treats `type
== "合集"`, `"collection"`, or `"系列"` as collections even when `collection_id` is nil. Those
collection cards will still run media-detail/TMDB/subscription preload paths that the comment says
are invalid and may end up marked failed. Use the normalized `isCollection` flag here.

-    guard partialMedia.collection_id == nil else { return }
+    guard !partialMedia.isCollection else { return }
```
