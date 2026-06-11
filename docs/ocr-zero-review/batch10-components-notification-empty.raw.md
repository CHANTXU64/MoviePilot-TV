```text
[ocr] Summary: 2 file(s) reviewed, 2 comment(s), ~57702 token(s) used (input: ~55406, output: ~2296), cache(read: ~20480, write: ~0), 1m46s elapsed

─── MoviePilot-TV/Views/Components/EmptyDataView.swift:49-51 ───
On tvOS this creates an invisible focus target when no action is available. Although it keeps focus
away from the navigation bar, users can land on a 1pt `Color.clear` with no visual feedback or
accessibility label, which can make remote navigation and VoiceOver confusing. Consider making the
empty-state content itself focusable with an accessibility label, or using an explicit focus
state/guide so the retained focus has a visible/announced target.



─── MoviePilot-TV/Views/Components/NotificationComponent.swift:34-34 ───
The toast is aligned to the top trailing edge without any outer padding or width constraint. On tvOS
this can place the capsule/shadow directly against the screen edge or safe-area boundary, and longer
notification messages may expand off-screen because `Text` has no wrapping/max-width limit. Consider
adding safe-area padding and constraining/wrapping the message so arbitrary NotificationManager
messages remain visible.

+        .frame(maxWidth: 600, alignment: .trailing)
+        .padding(.top, 60)
+        .padding(.trailing, 80)
         .transition(.move(edge: .top).combined(with: .opacity))
```
