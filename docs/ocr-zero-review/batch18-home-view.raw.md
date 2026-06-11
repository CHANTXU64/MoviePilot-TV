```text
[ocr]   ✘ file_read failed: file "MoviePilot-TV/Views/ContentView.swift" not found: git show 29853bd:MoviePilot-TV/Views/ContentView.swift: exit status 128: fatal: path 'MoviePilot-TV/Views/ContentView.swift' does not exist in '29853bd'

[ocr] Summary: 1 file(s) reviewed, 3 comment(s), ~420838 token(s) used (input: ~414732, output: ~6106), cache(read: ~185856, write: ~0), 3m46s elapsed

─── MoviePilot-TV/Views/Pages/HomeView.swift:169-169 ───
`MediaSectionView` now requires a `MediaActionHandler` environment object, but this change does not
provide it locally and the app root currently only injects `NotificationManager`. When the
latest-media section is rendered, SwiftUI will fail at runtime with a missing `EnvironmentObject`.
Please inject a shared `MediaActionHandler` above `HomeView` (or own one in `HomeView` and pass it
with `.environmentObject(...)`), and apply the related alert/overlay handling if these actions can
show handler state.



─── MoviePilot-TV/Views/Pages/HomeView.swift:310-310 ───
This focus key does not match the key used on the cards below: this produces `"123"` for a non-nil
optional id, while `.focused(..., equals: String(describing: item.id))` produces `"Optional(123)"`.
As a result, first-row focus redirection will not land on the first subscription card. Use one
helper to generate the same stable focus id in both places, and avoid `String(describing:)` for
optional IDs.



─── MoviePilot-TV/Views/Pages/HomeView.swift:407-413 ───
The destructive context-menu action deletes/cancels the subscription immediately. Existing
`deleteSubscribe` calls the server-side delete API and there is no confirmation dialog in this flow,
so an accidental remote/context-menu click can remove user subscription state without a recovery
step. Gate this with a confirmation dialog/alert before calling `deleteSubscribe`.
```
