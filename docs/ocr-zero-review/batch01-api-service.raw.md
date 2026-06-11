```text
[ocr] Summary: 1 file(s) reviewed, 6 comment(s), ~125404 token(s) used (input: ~120495, output: ~4909), cache(read: ~26112, write: ~0), 1m37s elapsed

─── MoviePilot-TV/Services/APIService.swift:232-234 ───
Falling back to `UserDefaults` for access tokens stores bearer credentials outside the Keychain if
`KeychainHelper.save` fails. That makes token exposure possible via backups/logical extraction and
also leaves any previously migrated plaintext token readable. Prefer failing the save/login (or
keeping only in memory) and cleaning up legacy `UserDefaults` token values instead of persisting
secrets there.

-        if !KeychainHelper.shared.save(token, service: "MoviePilot-TV", account: "accessToken") {
-          UserDefaults.standard.set(token, forKey: "accessToken")
+        guard KeychainHelper.shared.save(token, service: "MoviePilot-TV", account: "accessToken") else {
+          print("Failed to save access token to keychain")
+          return
         }
+        UserDefaults.standard.removeObject(forKey: "accessToken")


─── MoviePilot-TV/Services/APIService.swift:297-299 ───
This has the same sensitive-data issue for the user password: on Keychain failure it is persisted in
plaintext `UserDefaults`. Passwords should never have a plaintext fallback; if secure storage fails,
report the failure or keep the credential only for the current login attempt.

-        if !KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: "password") {
-          UserDefaults.standard.set(value, forKey: "password")
+        guard KeychainHelper.shared.save(value, service: "MoviePilot-TV", account: "password") else {
+          print("Failed to save password to keychain")
+          return
         }
+        UserDefaults.standard.removeObject(forKey: "password")


─── MoviePilot-TV/Services/APIService.swift:1124-1124 ───
`keyword` is interpolated into a URL path component without path-component encoding. A keyword
containing spaces, `/`, `?`, `%`, or non-ASCII characters can produce an invalid URL, change the
route, or inject query parameters before `buildEndpoint` adds its own query items. Encode dynamic
path segments with `.urlPathAllowed` (or a stricter per-component character set) before constructing
the path; the same pattern appears in other path-segment APIs such as media IDs, person IDs, hashes,
group IDs, and progress keys.

-        path: "/search/media/\(keyword)/stream",
+        path: "/search/media/\(keyword.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? keyword)/stream",


─── MoviePilot-TV/Services/APIService.swift:1067-1072 ───
Unlike `makeRequest`, the SSE path treats 401 as terminal and never attempts the existing
auto-login/token refresh flow. Streamed searches/progress will fail after token expiry even though
normal REST requests transparently recover. Consider sharing the 401 refresh logic here and retrying
the stream once with the refreshed token before finishing with `unauthorized`.



─── MoviePilot-TV/Services/APIService.swift:431-431 ───
`APIService` is `@MainActor`, so for all non-`MediaInfo` types this synchronous `JSONDecoder` work
runs on the main actor. Large payloads such as resource search results, transfer history,
subscriptions, or media-server lists can block tvOS focus/navigation. Either move generic decoding
to a background executor (as done for `MediaInfo`) or make the service methods non-main-actor and
hop to the main actor only for published state updates.



─── MoviePilot-TV/Services/APIService.swift:1397-1400 ───
This returns success when the response body is not one of the two decoded shapes, so a backend
failure payload with a different schema can be reported as successful to the UI. Prefer decoding the
common action response through one strict helper and throw `APIError.serverMessage`/`decodingError`
when the body is unrecognized instead of defaulting to success.

     if let resp = try? JSONDecoder().decode(SimpleResp.self, from: data) {
-      return resp.success ?? true
+      return resp.success ?? false
     }
-    return true
+    throw APIError.decodingError(
+      DecodingError.dataCorrupted(
+        DecodingError.Context(codingPath: [], debugDescription: "Unrecognized subscription response")
+      )
+    )
```
