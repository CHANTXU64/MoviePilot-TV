```text
[ocr] Summary: 1 file(s) reviewed, 2 comment(s), ~191661 token(s) used (input: ~186641, output: ~5020), cache(read: ~69120, write: ~0), 3m4s elapsed

─── MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift:35-35 ───
`onSeasonTap` is part of this view's public API and MediaDetailView passes it to navigate to the
full season page, but this file never invokes it. As a result, tapping a season in the embedded
shelf always subscribes/unsubscribes instead of performing the caller-provided navigation, making
the callback silently ineffective. Consider honoring the callback in the card's primary action (and
keeping subscribe/unsubscribe as the footer/context action if needed), or remove the parameter if
custom tap behavior is not supported.

  var onSeasonTap: ((TmdbSeason) -> Void)? = nil


─── MoviePilot-TV/Views/Pages/SubscribeSeasonView.swift:232-233 ───
This turns a missing `season_number` into season 0 for subscription, unsubscribe, and status lookup.
The model defines `season_number` as optional and the view model skips nil season numbers when
checking subscription state, so a malformed/partial season record would be shown and acted on as
specials season 0, potentially subscribing or cancelling the wrong season. Prefer guarding for a
real season number before rendering actionable controls, or disable the subscribe action when it is
absent.

-     let seasonNumber = season.season_number ?? 0
+     guard let seasonNumber = season.season_number else {
+       EmptyView()
+       return
+     }
      let isSubscribed = viewModel.isSeasonSubscribed(seasonNumber)
```
