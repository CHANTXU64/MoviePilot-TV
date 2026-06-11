```text
[ocr] Summary: 2 file(s) reviewed, 2 comment(s), ~258630 token(s) used (input: ~250108, output: ~8522), cache(read: ~106496, write: ~0), 3m47s elapsed

─── MoviePilot-TV/Views/Components/MediaContextMenu.swift:85-85 ───
This modifier now requires `SubscriptionHandler` from the SwiftUI environment, and
`MediaContextMenuItems` also requires `MediaActionHandler`, but the current app-level environment
injection only provides `NotificationManager`. As soon as this reusable modifier is attached to a
card/grid, SwiftUI will crash at runtime with a missing `EnvironmentObject` unless every call site
is under both injections. Consider either injecting both handlers at the app/screen root together
with `mediaActionAlerts()`, or make these dependencies explicit parameters of the modifier so usage
sites cannot omit them accidentally.



─── MoviePilot-TV/Views/Components/MediaContextMenu.swift:55-59 ───
These menu actions update `SubscriptionHandler` state (`forkSheetRequest`, `sheetSubscribe`, or
`tvSubscribeRequest` via `handleSubscribe`), but there is currently no view in the codebase
presenting UI from those `SubscriptionHandler` properties. Without a corresponding
`.sheet`/navigation/alert observer installed at the same hierarchy level, selecting “复用订阅” or
“订阅/分季订阅” will only mutate state and appear to do nothing. Please add the presentation wiring where
this modifier is used, or move it into this reusable component/modifier.
```
