```text
[ocr] Summary: 3 file(s) reviewed, 5 comment(s), ~649507 token(s) used (input: ~637295, output: ~12212), cache(read: ~260608, write: ~0), 9m7s elapsed

─── MoviePilot-TV/Views/Components/BestResultCard.swift:45-53 ───
`typeIcon(_:)` only recognizes Chinese display labels, but existing search data can carry
backend/raw type values such as `collection`, `movie`, or `tv` (for example collection search is
requested with `type=collection`, and `MediaInfo.checkIsCollection` already treats `collection` as a
collection). When a best-result collection/media item passes that raw value into this component, it
falls through to the default `film` icon and renders the wrong type. Consider normalizing the type
here or reusing the existing centralized mapping logic so both display labels and backend values are
handled consistently.

    private func typeIcon(_ type: String?) -> String {
-     switch type {
-     case "电影": return "film"
-     case "电视剧": return "tv"
-     case "合集": return "rectangle.stack"
-     case "人物": return "person.fill"
+     switch type?.lowercased() {
+     case "电影", "movie": return "film"
+     case "电视剧", "剧集", "tv": return "tv"
+     case "合集", "系列", "collection": return "rectangle.stack"
+     case "人物", "person": return "person.fill"
      default: return "film"
      }
    }


─── MoviePilot-TV/Views/Components/BestResultCard.swift:68-70 ───
Setting `isImageFailed` to `true` removes `KFImage` from the view tree, so a transient
download/auth/cache failure is never retried while the same card instance and `posterUrl` remain
alive. In the search best-result row this can leave the fallback icon stuck even after network or
cookie state recovers. Prefer letting Kingfisher keep showing the placeholder/fallback while
retaining its retry behavior, or add an explicit retry policy instead of permanently suppressing the
image for the current URL.

-           .onFailure { _ in
-             isImageFailed = true
-           }
+           .retry(maxCount: 2, interval: .seconds(1))


─── MoviePilot-TV/Views/Sheets/ForkSubscribeSheet.swift:26-26 ───
This sheet is rendering a SubscribeShare poster through a MediaInfo conversion, which recomputes the
URL with the generic media-poster path rules instead of the SubscribeShare URL that was already
precomputed for subscription posters. That can change URL handling for subscription/share poster
values and also repeats the conversion on every body recomputation. Prefer the share's own
`imageURLs.poster` here.

-         if !isImageFailed, let posterUrl = share.toMediaInfo().imageURLs.poster {
+         if !isImageFailed, let posterUrl = share.imageURLs.poster {


─── MoviePilot-TV/Views/Sheets/ForkSubscribeSheet.swift:87-96 ───
Each button press starts an independent fork request. Since `/subscribe/fork` is a POST that creates
a new subscription and `SubscriptionHandler.fork` does not guard concurrent calls, repeated remote
clicks can create duplicate subscriptions and trigger `onFork` multiple times. Track an in-flight
state and disable/ignore the button while the request is running.

            Button(action: {
-             // Fork a subscription
-             Task {
+             guard !isForking else { return }
+             isForking = true
+             Task { @MainActor in
+               defer { isForking = false }
                let newSubId = await subscriptionHandler.fork(share: share)
                if let newSubId = newSubId {
                  onFork(newSubId)
                  dismiss()
                }
              }
            }) {


─── MoviePilot-TV/Views/Sheets/MultiSelectionSheet.swift:54-70 ───
If `selected` already contains an ID that is also in `disabledOptions`, this row is rendered checked
and disabled, so the user cannot remove it and the parent may still submit a disabled option after
tapping confirm. If disabled options are intended to be unavailable choices, consider sanitizing
`selected` when the sheet appears/when `disabledOptions` changes, or render disabled rows with a
non-mutating state that cannot remain selected as a valid result.

```
