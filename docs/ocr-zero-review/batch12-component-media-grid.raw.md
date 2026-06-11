```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~123216 token(s) used (input: ~117986, output: ~5230), cache(read: ~44032, write: ~0), 2m11s elapsed

─── MoviePilot-TV/Views/Components/MediaGridView.swift:44-46 ───
Because `.equatable()` is applied to this wrapper, comparing only `item.id` can suppress updates
when the same media is refreshed with new display data (poster/title/rating/type/source) or changed
tap behavior (for example `subscribeShare`) under the same stable id. Compare the rendered item
state, or remove `.equatable()` if these fields are expected to change in place.

+private struct GridCardView: View, Equatable {
+  let item: MediaInfo
+  let onTap: () -> Void
+  let onFocus: (Bool) -> Void
+ 
 static func == (lhs: GridCardView, rhs: GridCardView) -> Bool {
-  lhs.item.id == rhs.item.id
+    lhs.item == rhs.item
 }


─── MoviePilot-TV/Views/Components/MediaGridView.swift:69-71 ───
This wrapper is also used with `.equatable()`, so an id-only comparison can leave the card and its
context menu rendered from stale `MediaInfo` when an item is updated without changing identity.
Include the item fields that affect rendering/menu behavior (or compare `item` directly) to avoid
stale UI/actions.

+private struct GridCardViewWithMenu<MenuContent: View>: View, Equatable {
+  let item: MediaInfo
+  let onTap: () -> Void
+  let onFocus: (Bool) -> Void
+  let menuBuilder: (MediaInfo) -> MenuContent
+ 
 static func == (lhs: GridCardViewWithMenu, rhs: GridCardViewWithMenu) -> Bool {
-  lhs.item.id == rhs.item.id
+    lhs.item == rhs.item
 }


─── MoviePilot-TV/Views/Components/MediaGridView.swift:240-244 ───
`isLoading`/`isLoadingMore` are passed into the component but not used before triggering pagination.
On tvOS, moving focus around the last rows can refocus multiple eligible cards before the parent
state settles, causing repeated `onLoadMore` calls for callers that do not internally deduplicate.
Guard the trigger with the loading flags (and clamp the threshold boundary for clarity).

-    if let index = items.firstIndex(where: { $0.id == item.id }),
-      index >= items.count - loadMoreThreshold
-    {
+    guard !isLoading, !isLoadingMore else { return }
+ 
+    let thresholdIndex = max(0, items.count - loadMoreThreshold)
+    if let index = items.firstIndex(where: { $0.id == item.id }), index >= thresholdIndex {
       onLoadMore(item.id)
     }
```
