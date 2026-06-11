```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~290080 token(s) used (input: ~284698, output: ~5382), cache(read: ~122368, write: ~0), 3m9s elapsed

─── MoviePilot-TV/Views/Pages/RecommendView.swift:39-46 ───
`MediaGridView` treats `SubscribeShare` items specially: a normal tap only invokes `onShareTapped`,
and `MediaContextMenuItems` sets `subscriptionHandler.forkSheetRequest` for “复用订阅”. This view does
not provide `onShareTapped` or present a `ForkSubscribeSheet`, so tapping a shared subscription does
nothing and the context-menu action only updates state without showing any UI. Mirror the Explore
page by wiring `onShareTapped` and adding a sheet bound to `forkSheetRequest`.

              contextMenu: { item in
                MediaContextMenuItems(
                  item: item,
                  navigationPath: $path,
                  subscriptionHandler: subscriptionHandler
                )
+             },
+             onShareTapped: { share in
+               subscriptionHandler.forkSheetRequest = share
              }
            )


─── MoviePilot-TV/Views/Pages/RecommendView.swift:40-44 ───
`MediaContextMenuItems` depends on `MediaActionHandler` via `@EnvironmentObject`, but the current
app root only injects `NotificationManager` and this new page does not provide a
`MediaActionHandler`. Opening this context menu can therefore fail at runtime with a missing
environment object. Ensure the handler is injected before this view/menu is rendered, or pass the
dependency explicitly.



─── MoviePilot-TV/Views/Pages/RecommendView.swift:66-66 ───
Setting `subscriptionHandler.forkSheetRequest` (from the context menu or an `onShareTapped`
callback) will not present anything unless this view also binds that state to `ForkSubscribeSheet`.
Without this sheet, the “复用订阅” flow is broken on the recommendation page.

      .mediaSubscriptionAlerts(using: subscriptionHandler, navigationPath: $path)
+     .sheet(item: $subscriptionHandler.forkSheetRequest) { share in
+       ForkSubscribeSheet(
+         share: share,
+         onFork: { newSubId in
+           Task {
+             await subscriptionHandler.fetchSubscriptionAndShowEditor(subId: newSubId)
+           }
+         },
+         subscriptionHandler: subscriptionHandler
+       )
+     }
```
