```text
[ocr] Summary: 4 file(s) reviewed, 6 comment(s), ~508837 token(s) used (input: ~497822, output: ~11015), cache(read: ~197632, write: ~0), 8m42s elapsed

─── MoviePilot-TV/ViewModels/CollectionDetailViewModel.swift:44-48 ───
`hasLoaded` is set before the asynchronous refresh completes, but `Paginator.refresh()` swallows
fetch errors into `paginator.hasError` instead of throwing. If the first collection request fails
(network/auth/server error), this flag remains true and later calls to `loadInitialData()` will be
ignored, leaving the detail page unable to retry its initial load through the same entry point.

    func loadInitialData() async {
      guard !hasLoaded else { return }
      hasLoaded = true
      await paginator.refresh()
+     if paginator.hasError {
+       hasLoaded = false
+     }
    }


─── MoviePilot-TV/ViewModels/PersonDetailViewModel.swift:109-117 ───
`hasLoaded` is set before either initial request completes. If the detail request or the first
credits page fails transiently, subsequent `.task` executions will return early and the page has no
retry path in the new view, leaving the profile or credits empty until the view model is recreated.
Consider marking it loaded only after the initial load succeeds, or resetting it when
`paginator.hasError` / detail loading fails so a retry can run.



─── MoviePilot-TV/ViewModels/PersonDetailViewModel.swift:113-116 ───
This does not express the intended parallelism clearly; the tuple expression can be read as normal
sequential evaluation, despite the comment saying the two loads run in parallel. Use `async let` or
a task group so the detail and credits requests are explicitly started concurrently and future
maintainers do not accidentally serialize the initial page load.

-     _ = await (
-       loadDetails(),
-       paginator.refresh()
-     )
+     async let details: Void = loadDetails()
+     async let credits: Void = paginator.refresh()
+     _ = await (details, credits)


─── MoviePilot-TV/ViewModels/PersonDetailViewModel.swift:102-104 ───
This diagnostic says the credits/works load failed, but this `catch` is in `loadDetails()` and
handles failures from `fetchPersonDetail`. The misleading message can send debugging in the wrong
direction; update it to mention person detail/profile loading.

    } catch {
-       print("加载人物作品出错: \(error)")
+       print("加载人物详情出错: \(error)")
    }


─── MoviePilot-TV/Views/Pages/PersonDetailView.swift:111-113 ───
The biography card is a preview that opens the full text in a sheet, but it renders the entire
biography without a line limit or height cap. Long biographies can consume/overflow the fixed 600pt
header area and make tvOS focus/layout behavior unstable. Consider truncating the preview and
leaving the complete text to the sheet.

                    Text(biography)
                      .font(.caption)
                      .multilineTextAlignment(.leading)
+                     .lineLimit(6)


─── MoviePilot-TV/Views/Pages/PersonDetailView.swift:0-0 ───
The full biography sheet is not scrollable, so longer biographies can be clipped off-screen and
become unreadable on tvOS. Wrap the sheet content in a ScrollView (or otherwise constrain it) so the
full text remains accessible.

+         ScrollView {
          VStack(alignment: .leading, spacing: 20) {
            Text(person.name ?? "个人简介")
              .font(.title2.bold())
 
            Text(biography)
              .font(.footnote)
          }
          .padding(50)
-         .frame(width: 1600)
+           .frame(width: 1600, alignment: .leading)
+         }

```
