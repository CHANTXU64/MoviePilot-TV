```text
[ocr] Summary: 8 file(s) reviewed, 17 comment(s), ~1048886 token(s) used (input: ~1023862, output: ~25024), cache(read: ~420352, write: ~0), 12m23s elapsed

─── MoviePilot-TV/App/MoviePilot-TVApp.swift:6-6 ───
`NotificationManager` is instantiated here but no definition is present in the project (search only
finds this usage). This will prevent the app target from compiling unless the type is added to the
target or the correct module is imported.



─── MoviePilot-TV/App/MoviePilot-TVApp.swift:10-10 ───
`ContentView` is used as the root view but no `ContentView` definition is present in the project
(search only finds this usage). Please add the root view to the target or update this entry point to
use the actual existing root view; otherwise the app will fail to compile.



─── MoviePilot-TV/Extensions/Formatters.swift:79-83 ───
This shared `RelativeDateTimeFormatter` instance can be called from any thread through the `String`
extension. Foundation formatter types are mutable and not generally safe for concurrent use, so
future SwiftUI tasks/background model mapping can race on this singleton and produce intermittent
incorrect output or crashes. Consider creating a formatter per call, confining the helper to
`@MainActor`, or protecting access with a lock/actor.

-   private static let relativeDateFormatter: RelativeDateTimeFormatter = {
+   private static func makeRelativeDateFormatter() -> RelativeDateTimeFormatter {
     let formatter = RelativeDateTimeFormatter()
     formatter.locale = Locale(identifier: "zh_CN")
     return formatter
-   }()
+   }


─── MoviePilot-TV/Extensions/Formatters.swift:88-90 ───
Parsing every backend date string with a fixed Shanghai region can misinterpret UTC/offset ISO-8601
timestamps or fail on common API formats with fractional seconds/time-zone suffixes. Since models in
this batch expose fields like `pubdate`, `date`, and `last_update`, this may display wrong relative
times or raw timestamps. Prefer an explicit parser chain for the backend formats (e.g.
ISO8601DateFormatter with fractional seconds and offsets) and only apply the display locale/time
zone after parsing the absolute date.

-    if let time = Date(self, region: CN_Region) {
-      return String.relativeDateFormatter.string(for: time) ?? self
+    if let date = ISO8601DateFormatter().date(from: self) {
+      return String.makeRelativeDateFormatter().localizedString(for: date, relativeTo: Date())
     }


─── MoviePilot-TV/Models/JobRegistry.swift:6-6 ───
`AppLanguage` is referenced by the new registry but is not defined anywhere else in `MoviePilot-TV/`
(only this file matches the symbol), so this file will fail to compile with `Cannot find type
'AppLanguage' in scope`. Add the `AppLanguage` enum/type before using it here, or replace it with
the project's existing locale representation if one already exists under a different name.



─── MoviePilot-TV/Models/Models.swift:210-213 ───
`APIService` is `@MainActor`, but this `Decodable` initializer can run from non-main decoding paths
(for example `APIService.decodeMediaInfoArrayInBackground` decodes `MediaInfoJSON`, including
`season_info`, on a global queue). Calling `APIService.shared` here crosses main-actor isolation
from a synchronous initializer, which can either fail under strict concurrency or race/stale-read
runtime state. Keep models/decoding pure and compute these URLs from a captured config after
decoding, as is already done for `MediaInfo` in the background decode path.



─── MoviePilot-TV/Models/Models.swift:682-682 ───
When all identifier fields are absent this returns a constant string made only of separators, so
unrelated unidentified media items all get the same `id`; `deduplicate` then drops all but the first
and SwiftUI identity can also collide. Add a fallback key using stable display fields (e.g.
title/original title/year/type/source) or avoid inserting all-empty keys into the dedup set.



─── MoviePilot-TV/Models/Models.swift:1500-1500 ───
`decodeIfPresent(PersonAvatar.self, ...)` still throws if the key is present but the object lacks
`normal` (for example an avatar dictionary containing only other image sizes), causing the whole
`Person` decode to fail. Since avatar formats vary across Douban/Bangumi/TMDB-style payloads,
consider making `PersonAvatar` tolerate other common image keys or decoding this field with `try?`
so a bad avatar does not break the cast/director list.



─── MoviePilot-TV/Services/KeychainHelper.swift:14-19 ───
Including `kSecAttrAccessible` in the lookup query makes the item identity depend on the current
accessibility policy. If a credential already exists with the same service/account but a different
accessibility class (for example from a previous version or a future policy change),
update/read/delete will not match it, and the add path can then fail with `errSecDuplicateItem`.
Keep lookup queries to stable identity attributes (`class/service/account`) and apply accessibility
only when adding or explicitly migrating the item.

     let query = [
       kSecClass: kSecClassGenericPassword,
       kSecAttrService: service,
       kSecAttrAccount: account,
-      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
     ] as [String: Any]


─── MoviePilot-TV/Services/KeychainHelper.swift:59-61 ───
The same lookup concern applies to reads: filtering by accessibility can make existing credentials
unreadable if their accessibility attribute differs. Since `kSecAttrAccessible` is an item attribute
rather than a stable key, omit it from `SecItemCopyMatching` queries unless you are intentionally
searching only for a specific migrated class.

         kSecClass: kSecClassGenericPassword,
-        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
         kSecReturnData: true,


─── MoviePilot-TV/Services/KeychainHelper.swift:58-60 ───
Deleting with `kSecAttrAccessible` in the query can leave same service/account credentials behind
when they were stored with a different accessibility class, which is especially risky for
logout/credential clearing paths. Delete by the stable key attributes only.

         kSecAttrAccount: account,
         kSecClass: kSecClassGenericPassword,
-        kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,


─── MoviePilot-TV/Services/KeychainHelper.swift:18-18 ───
This helper is used for access tokens and passwords, but the accessibility class is fixed to
`AfterFirstUnlockThisDeviceOnly`, which keeps secrets available after the first unlock even while
the device is locked. If these credentials are only needed during interactive app use, prefer
`WhenUnlockedThisDeviceOnly` (or make the accessibility class an explicit parameter) to reduce
credential exposure.

-      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
+      kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,


─── MoviePilot-TV/Services/KeychainHelper.swift:49-49 ───
Keychain diagnostics should go through the centralized `Logger` instead of direct `print`, so
release/debug behavior and future redaction/filtering remain consistent with the rest of the app.

-      print("Keychain save failed with unhandled status: \(status)")
+      Logger.error("Keychain save failed with unhandled status: \(status)")


─── MoviePilot-TV/Services/KeychainHelper.swift:81-81 ───
Same logging consistency issue here: use the app `Logger` rather than `print` for Keychain errors,
otherwise these messages bypass the Logger's DEBUG-only handler and any future centralized
filtering.

-        print("Keychain read failed with unhandled status: \(status)")
+        Logger.error("Keychain read failed with unhandled status: \(status)")


─── MoviePilot-TV/Services/Logger.swift:93-93 ───
`handler` is a mutable global that can be read by any logging call while `bootstrap(handler:)`
writes to it. If logging happens from background tasks while the handler is being replaced, this
creates an unsynchronized read/write data race. Consider making bootstrapping immutable/one-shot
during startup, or protecting access with a lock/actor (for example snapshot the handler under a
lock before invoking it).



─── Package.swift:21-22 ───
SwiftPM target names are used as Swift module names and must be valid identifiers. `MoviePilot-TV`
contains a hyphen, so `swift package` validation/build will fail before dependency resolution. Keep
the directory path/package display name if desired, but rename the target and update the library
product's `targets` entry to the same identifier.

     .target(
-      name: "MoviePilot-TV",
+      name: "MoviePilotTV",


─── Package.swift:28-30 ───
Because `sources: nil` includes every Swift file under `MoviePilot-TV`, this library target will
also compile `App/MoviePilot-TVApp.swift`, which contains the `@main` app entry point. That makes
the package product unsuitable as a reusable/testable library and can fail or create duplicate
entry-point/linkage problems for consumers. Split app bootstrap code out of the package target or
explicitly limit sources to non-App directories.

       path: "MoviePilot-TV",
-      exclude: [],
-      sources: nil  // Defaults to all source files in path
+      exclude: ["App"],
+      sources: ["Extensions", "Models", "Services"]
```
