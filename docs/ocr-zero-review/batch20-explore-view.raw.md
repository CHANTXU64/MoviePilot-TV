```text
[ocr] Summary: 1 file(s) reviewed, 1 comment(s), ~466558 token(s) used (input: ~461806, output: ~4752), cache(read: ~212992, write: ~0), 3m56s elapsed

─── MoviePilot-TV/Views/Pages/ExploreView.swift:8-8 ───
`ExploreView` requires a `MediaActionHandler` environment object, and the context menu created below
also reads the same environment object. In the current app root only `NotificationManager` is
injected, so mounting this page or opening its media context menu can crash at runtime with a
missing `EnvironmentObject`. Either inject a `MediaActionHandler` from an ancestor, or let this page
own one and pass it into the subtree (also attach the alert modifier if the handler’s alert/loading
state should be visible).

-  @EnvironmentObject private var mediaActionHandler: MediaActionHandler
+  @StateObject private var mediaActionHandler = MediaActionHandler()
```
