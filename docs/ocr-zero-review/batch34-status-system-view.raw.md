```text
[ocr] Summary: 3 file(s) reviewed, 3 comment(s), ~341669 token(s) used (input: ~332589, output: ~9080), cache(read: ~128000, write: ~0), 10m0s elapsed

─── MoviePilot-TV/ViewModels/StatusViewModel.swift:20-22 ───
Because the three dashboard sections are independent, a failure in an earlier `try await`
cancels/skips the later assignments when the `async let` scope exits. For example, if
`/dashboard/statistic` fails transiently, storage and downloader data are not updated even if their
requests would succeed. Consider awaiting each request as a `Result` (or using separate `do/catch`
blocks) so one failed endpoint does not block the other cards from refreshing.

-       statistic = try await stat
-       storage = try await stor
-       downloader = try await down
+       let statResult = await Result { try await stat }
+       let storResult = await Result { try await stor }
+       let downResult = await Result { try await down }
+ 
+       if case .success(let value) = statResult { statistic = value }
+       if case .success(let value) = storResult { storage = value }
+       if case .success(let value) = downResult { downloader = value }
+ 
+       if case .failure(let error) = statResult { print("Error fetching statistic data: \(error)") }
+       if case .failure(let error) = storResult { print("Error fetching storage data: \(error)") }
+       if case .failure(let error) = downResult { print("Error fetching downloader data: \(error)") }


─── MoviePilot-TV/Views/Pages/StatusView.swift:16-19 ───
This renders the empty state while the first `.task` refresh is still in flight, so a normal initial
load or transient request failure is indistinguishable from genuinely empty data. Consider exposing
loading/error state from `StatusViewModel` and showing a `ProgressView` or error message before
falling back to `EmptyDataView`.



─── MoviePilot-TV/Views/Pages/SystemView.swift:177-179 ───
After logout this only updates the credential status, while `serverURL`, `username`, and
`backendVersion` remain whatever was loaded before. Because the connection section is shown whenever
`serverURL` is non-empty, the page can still display the previous account/server details after
credentials have been cleared. Clear or reload the displayed session fields together with the logout
state so the UI does not expose stale login information.

            APIService.shared.logout()
-             // 登出后立即刷新状态
+             // 登出后立即刷新状态，并清空已加载的账户信息，避免显示旧登录状态
            viewModel.checkKeychainStatus()
+             viewModel.serverURL = ""
+             viewModel.username = ""
+             viewModel.backendVersion = nil
```
