```text
[ocr] Summary: 2 file(s) reviewed, 6 comment(s), ~823291 token(s) used (input: ~814681, output: ~8610), cache(read: ~357376, write: ~0), 4m5s elapsed

─── MoviePilot-TV/Services/StaffManager.swift:117-125 ───
`mergeCrew` returns `Person.job` translated for display, but this same API is documented as the
incremental load-more merge API. If the caller passes the previous return value back as `existing`,
`existingPerson.job` is no longer the canonical job key (e.g. it may be `导演`), so the next merge
combines localized labels with English keys and later priority lookup / deduplication becomes
inconsistent. Keep `Person.job` canonical through merge APIs and translate only at the view
boundary, or store the localized label in a separate display field.

-    return result.map { person in
-      var translatedPerson = person
-      if let jobKeys = person.job {
-        // job 字段此时存储的是英文 key, e.g., "Director/Writer"
-        // 我们需要把它翻译成当前选择的语言
-        translatedPerson.job = TranslationHelper.translateJobs(jobString: jobKeys)
-      }
-      return translatedPerson
-    }
+    return result


─── MoviePilot-TV/Services/StaffManager.swift:191-193 ───
This grouping path assumes `staff.job` contains English canonical job keys, but
`processCrew`/`mergeCrew` currently return translated job labels. If processed staff is passed here,
`getPriority(for:)` falls back to 999, `GroupedStaff.id` becomes localized text, and `translateJobs`
is applied to already-localized labels. Consider normalizing this function to accept only canonical
jobs (and avoid translating in `mergeCrew`), or add a separate canonical job field used for
grouping/sorting.



─── MoviePilot-TV/Services/StaffManager.swift:258-260 ───
`BangumiImages` can be non-nil while all URL fields are nil/empty, so this treats a person without a
displayable avatar as having one and can incorrectly prioritize them above people with real profile
images. Check for at least one non-empty image URL instead of only `images != nil`.

-    if person.images != nil {
-      return true
+    if let images = person.images {
+      return [images.large, images.common, images.medium, images.small, images.grid]
+        .contains { ($0?.isEmpty == false) }
     }


─── MoviePilot-TV/Services/TranslationHelper.swift:13-13 ───
`currentLanguage` is mutable global state read by all translation methods. If settings/UI code
updates it while async staff/network processing is formatting jobs, Swift can hit a data race and
produce mixed-language output. Consider making this immutable per call (pass `AppLanguage` into
translation methods) or isolating access behind `@MainActor`/an actor/lock.

-  static var currentLanguage: AppLanguage = .zhHans
+  @MainActor static var currentLanguage: AppLanguage = .zhHans


─── MoviePilot-TV/Services/TranslationHelper.swift:502-504 ───
These lookups require an exact lowercase ISO-639 key, so valid inputs such as `"EN"` or regional
tags like `"zh-CN"` will fall through and display the raw code. Normalize before lookup (for
example, lowercase and strip the region subtag) to make the helper robust to API/model variations.

   static func languageName(for code: String) -> String {
-    return languageNames[code]?[currentLanguage] ?? code
+    let normalizedCode = code
+      .trimmingCharacters(in: .whitespacesAndNewlines)
+      .lowercased()
+      .components(separatedBy: CharacterSet(charactersIn: "-_"))
+      .first ?? code
+    return languageNames[normalizedCode]?[currentLanguage] ?? code
   }


─── MoviePilot-TV/Services/TranslationHelper.swift:511-513 ───
Country codes are looked up case-sensitively, so lowercase or whitespace-padded ISO-3166 values from
another backend/model path will display as raw codes. Normalize to uppercase before the dictionary
lookup; apply the same normalization in `countryName(for country:)` as well.

   static func countryName(for code: String) -> String {
-    return countryNames[code]?[currentLanguage] ?? code
+    let normalizedCode = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
+    return countryNames[normalizedCode]?[currentLanguage] ?? code
   }
```
