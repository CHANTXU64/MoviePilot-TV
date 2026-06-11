```text
[ocr] Summary: 1 file(s) reviewed, 2 comment(s), ~155924 token(s) used (input: ~151619, output: ~4305), cache(read: ~64512, write: ~0), 4m24s elapsed

─── MoviePilot-TV/Views/Pages/LoginView.swift:34-38 ───
The button action starts an unstructured login task each time it is activated, while
`LoginViewModel.login()` has no internal `isLoading` guard. Rapid remote/keyboard submissions can
enqueue multiple login attempts before the disabled state is visually/applied, which may race
updates to `APIService.baseURL`, token, and `errorMessage`. Consider making login idempotent by
guarding `!isLoading` inside the view model (preferred), or otherwise preventing re-entry before
creating a new task.



─── MoviePilot-TV/Views/Pages/LoginView.swift:46-46 ───
This only rejects exactly empty raw strings. A server URL with leading/trailing whitespace or a
malformed value can still be submitted; `LoginViewModel` assigns it directly to
`APIService.baseURL`, and requests are later built with `URL(string: "\(baseURL)/api/v1...")`, so
users can get confusing failures or persist an unusable base URL. Trim/validate the server URL
(scheme + host) before enabling/submitting, and consider trimming the username while leaving the
password unchanged.

-          .disabled(viewModel.isLoading || viewModel.serverURL.isEmpty || viewModel.username.isEmpty || viewModel.password.isEmpty)
+          .disabled(
+            viewModel.isLoading
+              || viewModel.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
+              || viewModel.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
+              || viewModel.password.isEmpty
+          )
```
