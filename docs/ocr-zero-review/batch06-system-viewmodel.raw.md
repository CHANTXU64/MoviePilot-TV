```text
[ocr] Summary: 1 file(s) reviewed, 2 comment(s), ~243301 token(s) used (input: ~237317, output: ~5984), cache(read: ~105472, write: ~0), 2m36s elapsed

─── MoviePilot-TV/ViewModels/SystemViewModel.swift:257-259 ───
Because `SystemViewModel` is annotated with `@MainActor`, these static helpers are also main-actor
isolated. `CustomFilterService.applyHardAndSoftFilter` currently calls
`currentSelectedHardFilterRuleId()` / `currentSelectedSoftFilterRuleId()` from a non-main-actor
async context without `await`, so adding this file can trigger a Swift actor-isolation compile
error. Either make these read-only helpers explicitly `nonisolated` (and avoid accessing main-actor
state such as `APIService.shared.baseURL` inside them), or update all call sites to await the
main-actor hop.



─── MoviePilot-TV/ViewModels/SystemViewModel.swift:109-114 ───
The per-account settings key uses the raw `baseURL` string, but `LoginViewModel` stores the server
URL exactly as entered. Equivalent values such as `http://host:3000` and `http://host:3000/` will
generate different keys, making default sites/filter selections appear lost after the user edits or
re-enters the same server URL in a slightly different form. Normalize at least whitespace and
trailing slashes before composing the key.

-    let baseURL = APIService.shared.baseURL
+    let rawBaseURL = APIService.shared.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
+    let baseURL = rawBaseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
     let username =
       KeychainHelper.shared.read(service: "MoviePilot-TV", account: "username")
       ?? UserDefaults.standard.string(forKey: "username")
       ?? "default"
     return "\(prefix)_\(baseURL)_\(username)"
```
