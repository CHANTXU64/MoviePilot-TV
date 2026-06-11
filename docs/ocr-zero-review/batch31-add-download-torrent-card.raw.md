```text
[ocr] Summary: 3 file(s) reviewed, 7 comment(s), ~361468 token(s) used (input: ~349500, output: ~11968), cache(read: ~122368, write: ~0), 12m43s elapsed

─── MoviePilot-TV/ViewModels/AddDownloadViewModel.swift:68-68 ───
`Int(tmdbId)` silently turns any non-empty invalid value into `nil`, so a pasted or otherwise
invalid TMDB ID is submitted as if no override was provided. Consider validating `tmdbId` before
building the request and surfacing an error when it is non-empty but not a valid integer.

-     let tmdbIdInt = Int(tmdbId)
+     let trimmedTmdbId = tmdbId.trimmingCharacters(in: .whitespacesAndNewlines)
+     let tmdbIdInt: Int?
+     if trimmedTmdbId.isEmpty {
+       tmdbIdInt = nil
+     } else if let parsedTmdbId = Int(trimmedTmdbId) {
+       tmdbIdInt = parsedTmdbId
+     } else {
+       errorMessage = "TMDB ID 格式不正确"
+       return
+     }


─── MoviePilot-TV/ViewModels/AddDownloadViewModel.swift:81-81 ───
This pre-encoding result is discarded, while `APIService.addDownload` encodes the same payload again
before sending it. Keeping encoding in two layers adds unnecessary work and makes failures appear to
originate from the view model instead of the API layer; consider removing this line and letting
`APIService` own request encoding.



─── MoviePilot-TV/Views/Components/TorrentCard.swift:73-74 ───
If `meta.subtitle` is present but an empty string, the nil-coalescing operator selects it and
suppresses a non-empty `torrent.description`, so the card can omit useful torrent details. Prefer
choosing the first non-empty value before deciding whether to render the description.

-         let descriptionText = meta.subtitle ?? torrent.description
-         let shouldShowDescription = (descriptionText?.isEmpty == false)
+         let descriptionText = [meta.subtitle, torrent.description]
+           .compactMap { $0 }
+           .first { !$0.isEmpty }
+         let shouldShowDescription = descriptionText != nil


─── MoviePilot-TV/Views/Components/TorrentCard.swift:105-106 ───
When the factors indicate a promotion but `volume_factor` is nil or empty, this still renders an
empty padded badge. Gate the badge on a non-empty label (or provide a fallback based on the numeric
factors) to avoid blank UI elements.

-             if torrent.downloadvolumefactor != 1 || torrent.uploadvolumefactor != 1 {
-               Text(torrent.volume_factor ?? "")
+             if (torrent.downloadvolumefactor != 1 || torrent.uploadvolumefactor != 1),
+                let volumeFactor = torrent.volume_factor,
+                !volumeFactor.isEmpty {
+               Text(volumeFactor)


─── MoviePilot-TV/Views/Components/TorrentCard.swift:10-10 ───
This stored APIService reference is never used in the view. Keeping an unused service dependency
makes the component look like it performs network work directly and adds unnecessary coupling;
remove it unless it is needed by this card.



─── MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift:151-157 ───
This dismisses the sheet for every `errorMessage`, including recoverable submit failures from
`addDownload()`. Because the form is closed immediately, users cannot adjust the
downloader/path/TMDB ID or retry after a transient network/API error. Consider only dismissing for
unrecoverable configuration-load failures, or keep the sheet open for submission errors and let the
user retry.



─── MoviePilot-TV/Views/Sheets/AddDownloadSheet.swift:8-8 ───
`isInfoSectionFocused` is never read or assigned in this view, so it adds dead focus state and makes
the intended focus behavior harder to follow. Please remove it or wire it to the relevant control if
focus management is still needed.

```
