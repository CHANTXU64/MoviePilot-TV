```text
[ocr] Summary: 4 file(s) reviewed, 7 comment(s), ~266030 token(s) used (input: ~252436, output: ~13594), cache(read: ~98304, write: ~0), 5m21s elapsed

─── MoviePilot-TV/Views/Components/SheetPicker.swift:25-25 ───
`options` can be empty, but the picker still opens and the detail sheet renders an empty list. For a
generic sheet component this is a reachable boundary case during async loading/filtering and leaves
the user with a blank modal and no selectable action. Consider disabling the opener when there are
no options, or provide an empty state plus an explicit close action in the sheet.

     Button(action: { showingPicker = true }) {
+      // ...
+    }
+    .disabled(options.isEmpty)


─── MoviePilot-TV/Views/Components/SheetPicker.swift:55-56 ───
`title` is passed into `SheetPickerDetailView` but the sheet never presents it or any toolbar
dismissal affordance. On tvOS, a sheet containing only option buttons has weak context for
users/screen readers and no obvious cancel path when the user does not want to change the value.
Consider adding a navigation title and a toolbar close/cancel button bound to `isPresented`.

     NavigationStack {
       ScrollView {
+        // ...
+      }
+      .navigationTitle(title)
+      .toolbar {
+        ToolbarItem(placement: .cancellationAction) {
+          Button("取消") { isPresented = false }
+        }
+      }


─── MoviePilot-TV/Views/Components/SheetStyles.swift:43-53 ───
This custom `ToggleStyle` renders the toggle as a plain `Button` and only changes the icon visually.
On tvOS this can cause assistive technologies to announce it as a button without the current on/off
state, so users relying on VoiceOver/Switch Control may not know the selected value. Please expose
the toggle state through accessibility metadata (or otherwise preserve Toggle semantics) when
replacing the native control visuals.

     Button {
       configuration.isOn.toggle()
     } label: {
       HStack {
         configuration.label
         Spacer()
         Image(systemName: configuration.isOn ? "checkmark.circle.fill" : "circle")
       }
       .padding(.horizontal)
     }
     .buttonStyle(SheetToggleButtonStyle(isOn: configuration.isOn))
+    .accessibilityElement(children: .combine)
+    .accessibilityValue(configuration.isOn ? Text("On") : Text("Off"))
+    .accessibilityAddTraits(configuration.isOn ? .isSelected : [])


─── MoviePilot-TV/Views/Components/SheetTextField.swift:79-83 ───
Blocking `_UITextFieldCanvasView` here is risky because it is an internal `UITextField` subview that
may own text/caret/selection rendering on some tvOS releases. If UIKit adds that view after
initialization, this override can make the field stop displaying or editing text, and it is also
fragile across OS updates. Consider only filtering the known blur/effect views (e.g.
`UIVisualEffectView`/Backdrop) or hiding/removing visual-effect subviews after UIKit has built the
text field instead of preventing canvas subviews from being added.

-    if className.contains("Backdrop") || className.contains("VisualEffect")
-      || className.contains("_UITextFieldCanvasView")
-    {
+    if className.contains("Backdrop") || className.contains("VisualEffect") {
       return
     }


─── MoviePilot-TV/Views/Components/ShelfPicker.swift:5-6 ───
`RecommendShelf` is introduced as the component’s model type, but there is no definition or import
for it in the current codebase. This will prevent this new file from compiling unless the type is
added in the same target or imported from the module that defines it.



─── MoviePilot-TV/Views/Components/ShelfPicker.swift:17-24 ───
The redirector can assign a stale or invalid focus id when `selectedShelf` is non-nil but no longer
exists in `shelves`; in that case tvOS has no matching `.focused(..., equals:)` chip to move to. It
also leaves the invisible redirector focusable when `shelves` is empty. Resolve the target from the
current `shelves` before setting focus, and avoid making the redirector focusable when there is no
valid target.

-        .focusable(focusedShelfId == nil)
+        .focusable(focusedShelfId == nil && !shelves.isEmpty)
         .focused($isTopRedirectorFocused)
         .onChange(of: isTopRedirectorFocused) { _, isFocused in
           if isFocused {
-            focusedShelfId = selectedShelf?.id ?? shelves.first?.id
+            focusedShelfId = shelves.first(where: { $0.id == selectedShelf?.id })?.id ?? shelves.first?.id
             isTopRedirectorFocused = false
           }
         }


─── MoviePilot-TV/Views/Components/ShelfPicker.swift:45-52 ───
Same focus-target validation is needed here as for the top redirector. When `selectedShelf` is stale
or `shelves` is empty, this can focus an invisible 1-point redirector without a valid shelf chip
target.

-        .focusable(focusedShelfId == nil)
+        .focusable(focusedShelfId == nil && !shelves.isEmpty)
         .focused($isBottomRedirectorFocused)
         .onChange(of: isBottomRedirectorFocused) { _, isFocused in
           if isFocused {
-            focusedShelfId = selectedShelf?.id ?? shelves.first?.id
+            focusedShelfId = shelves.first(where: { $0.id == selectedShelf?.id })?.id ?? shelves.first?.id
             isBottomRedirectorFocused = false
           }
         }
```
