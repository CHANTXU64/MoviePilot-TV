```text
[ocr] Summary: 2 file(s) reviewed, 7 comment(s), ~354134 token(s) used (input: ~343672, output: ~10462), cache(read: ~131072, write: ~0), 10m53s elapsed

─── MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift:60-61 ───
`loadData()` can be re-entered while the first call is suspended at an `await` because `@MainActor`
does not make the whole async function atomic. If two callers enter before `isCreatedAndPaused` is
set, both can pass the new-subscription branch and create duplicate backend subscriptions. Add an
early `isLoading` guard or a separate initialization task/flag before the first await.

+     guard !isLoading else { return }
      isLoading = true
      defer { isLoading = false }


─── MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift:0-0 ───
After `addSubscription` succeeds, either pausing or fetching the full subscription can throw. The
catch below only logs and returns, leaving the newly created backend subscription behind; because
`isCreatedAndPaused` remains false, a later retry can create another subscription for the same
media. Track the created id and roll it back (or mark it as created and avoid a second POST) when
any later initialization step fails.

+         do {
          // 立即暂停
          _ = try await apiService.updateSubscriptionStatus(id: newId, state: "S")
 
          // 获取完整的订阅详情（以获得服务器端的默认值）
          let fullSubscribe = try await apiService.fetchSubscription(id: newId)
+           self.subscribe = fullSubscribe
+         } catch {
+           _ = try? await apiService.deleteSubscription(id: newId)
+           throw error
+         }


─── MoviePilot-TV/ViewModels/SubscribeSheetViewModel.swift:134-138 ───
These follow-up side effects run in the same `do` block as the persisted save. If `saveSubscription`
succeeds but resume/search throws, `save()` returns `false` and never sets `isSaved`; the sheet can
then treat the already-saved new subscription as canceled and roll it back. Consider marking the
save as successful and notifying the UI immediately after persistence, then run resume/search as
best-effort operations with separate error handling.



─── MoviePilot-TV/Views/Sheets/SubscribeSheet.swift:294-300 ───
This `onDisappear` is attached to the conditional form branch, so it can run when the form is
temporarily removed from the hierarchy (for example when `isLoading` flips during `loadData()`), not
only when the subscribe sheet is actually dismissed. Since `cancel()` deletes a newly-created
subscription, consider moving cleanup to a dismissal-specific path or gating it with an explicit
user-cancel/dismiss flag to avoid destructive rollback on lifecycle transitions.



─── MoviePilot-TV/Views/Sheets/SubscribeSheet.swift:44-47 ───
Invalid or empty numeric input is converted directly with `Int($0)`, which silently stores `nil`;
the getter then renders that `nil` as `"0"`. This can make a cleared/malformed value reappear as
zero and may send invalid episode ranges to the API. Consider validating the input (e.g. allow only
positive ranges, keep empty as empty text, and block save with a visible error when invalid).



─── MoviePilot-TV/Views/Sheets/SubscribeSheet.swift:54-57 ───
Invalid or empty numeric input is converted directly with `Int($0)` and there is no validation that
the start episode is positive or within `total_episode`. This can persist `nil`, zero, negative, or
out-of-range values and produce incorrect subscription rules. Please validate before
updating/saving, and preserve an empty UI state instead of forcing it back to `"0"`.



─── MoviePilot-TV/Views/Sheets/SubscribeSheet.swift:257-262 ───
When `viewModel.save()` returns `false`, the sheet stays open but the user gets no visible error
message; the view model currently only logs failures. Please surface a failure state here
(alert/toast/inline message) so API/configuration errors are actionable instead of appearing as a
button that simply stops loading.

```
