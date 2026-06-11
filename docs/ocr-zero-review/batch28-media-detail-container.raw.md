```text
[ocr] Summary: 1 file(s) reviewed, 2 comment(s), ~191705 token(s) used (input: ~187829, output: ~3876), cache(read: ~73728, write: ~0), 3m56s elapsed

─── MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift:266-271 ───
This new file references `MediaDetailView`, but no `MediaDetailView` type exists in the current
project, so the target will fail to compile. Please add the corresponding detail view implementation
in this batch or update this container to use the existing detail page type if it has a different
name.



─── MoviePilot-TV/Views/Pages/MediaDetailContainerView.swift:251-255 ───
Collection items can reach this destination from the shared grid navigation path, but
`MediaPreloadTask.start()` returns early for `collection_id != nil` without setting `isDetailReady`
or `isDetailFailed`. In that case `isReady` never becomes true and the loading overlay remains
indefinitely. Please route collections to `CollectionDetailView` before creating this container, or
make this container treat collection media as a separate ready state.

    private var isReady: Bool {
-     wasPreloaded
+     media.collection_id != nil
+       || wasPreloaded
        || ((preloadTask.isDetailReady && isContentReady) && minTimeElapsed)
        || preloadTask.isDetailFailed
    }

```
