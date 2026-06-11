```text
[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~498396 token(s) used (input: ~491760, output: ~6636), cache(read: ~199168, write: ~0), 7m12s elapsed

─── MoviePilot-TV/Views/Pages/MediaDetailView.swift:432-434 ───
For TV items that are not directly subscribable, pressing the primary "分季订阅" button only writes to
the boolean focus state on the content container. That container is not a concrete focusable season
item, and the existing page transition/scroll is only driven from `onChange(of: isHeroFocused)`, so
this action can be a no-op while focus remains on the hero button. Since `heroSection` already has
the `scrollProxy`, scroll to the season shelf (and then move focus to a real child if available)
when this button is selected.

              } else if detail.type == "电视剧" && detail.tmdb_id != nil {
-                 isContentFocused = true
+                 withAnimation(.easeInOut(duration: 0.6)) {
+                   showContentPage = true
+                   scrollProxy.scrollTo("seasonSubscriptionSection", anchor: .top)
+                 }
              }


─── MoviePilot-TV/Views/Pages/MediaDetailView.swift:297-301 ───
The unsubscribe confirmation flow is currently unreachable: `showUnsubscribeConfirm` and
`cancelSubscription()` are defined below, but when the media is already subscribed this handler only
shows an "already subscribed" alert. If the detail page is expected to support cancellation from the
primary subscription button, trigger the confirmation here; otherwise the dead alert/cancel state
should be removed to avoid misleading future maintenance.

    if isSubscribed {
-       showSubscribedAlert = true
+       showUnsubscribeConfirm = true
    } else {
      sheetSubscribe = viewModel.buildSubscribeRequest()
    }


─── MoviePilot-TV/Views/Pages/MediaDetailView.swift:218-219 ───
This only cancels the debounce preloads. The focus handlers below also start paginator loads
(`actorsPaginator.loadMore`, `recommendPaginator.loadMore`, `similarPaginator.loadMore`) that can
keep running after this view disappears because they are launched as unstructured tasks and the
paginator exposes `cancel()`. Cancel those loads here as well to avoid unnecessary network work and
late model updates after navigation away.

      recommendPreloadDebounce?.cancel()
      similarPreloadDebounce?.cancel()
+       viewModel.actorsPaginator.cancel()
+       viewModel.recommendPaginator.cancel()
+       viewModel.similarPaginator.cancel()
```
