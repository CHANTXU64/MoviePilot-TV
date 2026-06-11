```text
[ocr] Summary: 2 file(s) reviewed, 6 comment(s), ~312955 token(s) used (input: ~303600, output: ~9355), cache(read: ~125440, write: ~0), 4m39s elapsed

─── MoviePilot-TV/Views/Components/MediaCard.swift:62-62 ───
When `typeText` is nil or empty, the symbols block still tags an empty `Group` as `typeIcon`, so
`resolveSymbol(id:)` can succeed and draw a small empty top-left badge. This makes cards that
intentionally omit a type badge still show a blank background. Gate the drawing on a non-empty
`typeText` before resolving/drawing the symbol.

-      if let symbol = context.resolveSymbol(id: "typeIcon") {
+      if let type = typeText, !type.isEmpty, let symbol = context.resolveSymbol(id: "typeIcon") {


─── MoviePilot-TV/Views/Components/MediaCard.swift:19-24 ───
`MediaInfo` already carries an explicit `source` field (`themoviedb`/`douban`/`bangumi`), but this
inference ignores it and always prefers TMDB whenever `tmdb_id` is present. For Douban/Bangumi items
that also have a recognized TMDB id, the card will display the TMDB source icon instead of the
actual metadata source. Prefer `mediaInfo.source` when it is valid, then fall back to ID inference.

   static func from(mediaInfo: MediaInfo) -> MediaSource? {
+    if let source = mediaInfo.source, let mediaSource = MediaSource(rawValue: source) {
+      return mediaSource
+    }
     if mediaInfo.tmdb_id != nil { return .tmdb }
     if mediaInfo.douban_id != nil { return .douban }
     if mediaInfo.bangumi_id != nil { return .bangumi }
     return nil
   }


─── MoviePilot-TV/Views/Components/MediaCard.swift:258-258 ───
This parameter is stored but never applied in `posterContent`, so callers setting
`isBackgroundBlurred` (e.g. special "view all" cards) will see no effect. Either remove the option
or apply the blur to the loaded/placeholder poster content.



─── MoviePilot-TV/Views/Components/MediaCard.swift:467-469 ───
This equality only checks `id` and `showBadges`, but the view body also renders title, poster URL,
type, rating, source, and captures `onTap`. When this wrapper is used with `.equatable()`, refreshed
metadata for the same media id can be skipped and the card can show stale content. Include the
rendered fields in equality, or remove the Equatable optimization unless the data is guaranteed
immutable for a given id.



─── MoviePilot-TV/Views/Components/PersonCard.swift:27-31 ───
Because `action` is optional, this card can become a focusable tvOS target that does nothing when
the Siri Remote select button is pressed. That creates a dead stop in the Focus Engine for read-only
usages. Either make `action` non-optional for this component, or only enable focus/tap affordances
when an action is available.

-        .focusable(true)
+        .focusable(action != nil)
         .focused($isFocused)
         .onTapGesture {
-          action?()
+          guard let action else { return }
+          action()
         }


─── MoviePilot-TV/Views/Components/PersonCard.swift:40-40 ───
This fallback only covers `nil`; an empty or whitespace-only name from the API will render as a
blank title. Normalizing the string here keeps malformed person data from producing an empty card
label.

-        Text(person.name ?? "未知")
+        Text(person.name.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "未知")
```
