```text
[ocr] Summary: 2 file(s) reviewed, 3 comment(s), ~497080 token(s) used (input: ~485987, output: ~11093), cache(read: ~210944, write: ~0), 12m34s elapsed

─── MoviePilot-TV/ViewModels/ReorganizeViewModel.swift:42-49 ───
`target_path` immediately changes in the bound picker, but the dependent fields (`target_storage`,
`transfer_type`, `scrape`, folder flags) are only reconciled after this 100ms debounce. If the user
selects a target directory and quickly presses “开始整理”, `submit` can send the new `target_path`
together with stale/default derived options. Consider updating synchronously for user-driven picker
changes, or calling `updateForm(for: form.target_path)` at the start of `submit` before encoding the
form.



─── MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift:13-13 ───
`recognizeSource` is captured once when the sheet is initialized, but `APIService.settings` is
populated/refreshed asynchronously elsewhere. If this sheet is created before `fetchSettings()`
completes (or after settings change), the UI will keep the default `themoviedb` branch and show the
wrong ID field, so users may submit `tmdbid` while the backend expects `doubanid` (or vice versa).
Consider making the API service an observed object / moving this value into the view model and
deriving it from the current published settings instead of a stored `let`.



─── MoviePilot-TV/Views/Sheets/ReorganizeSheet.swift:142-148 ───
For non-empty but non-numeric input (for example pasted text), this setter leaves the previous
`tmdbid` unchanged while the field text is driven from `tmdbid`. That can silently submit an old ID
even though the user attempted to replace it with a different value. Prefer storing the raw text
separately and validating on submit, or explicitly clear/show an error for invalid input.

```
