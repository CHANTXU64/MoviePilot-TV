```text
[ocr] Summary: 3 file(s) reviewed, 3 comment(s), ~531556 token(s) used (input: ~520114, output: ~11442), cache(read: ~228864, write: ~0), 5m30s elapsed

─── MoviePilot-TV/Views/Components/ActionRow.swift:181-181 ───
The trailing action buttons are only hidden with `opacity(0)` when the row is inactive, but they
remain in the tvOS focus hierarchy because each button is still rendered and bound to
`focusedField`. This can let the Focus Engine land on an invisible action from a neighboring view
and make hidden actions selectable unexpectedly. Consider disabling/removing action focus while
inactive, e.g. gate the buttons with `isRowActive`/content focus or add an explicit
disabled/focusable condition so hidden actions cannot receive focus.

           .focused($focusedField, equals: .action(actionDesc.id))
+          .disabled(!isRowActive || !actionDesc.isEnabled)
+          .focusable(isRowActive)


─── MoviePilot-TV/Views/Components/SubscriptionModifier.swift:65-66 ───
`alertTitle` and `alertMessage` are captured as plain values when the modifier is built, while
`SubscriptionHandler.showAlert(title:message:)` mutates these `@Published` properties immediately
before setting `showAlert`. Because this modifier does not observe the handler directly, SwiftUI can
present the alert with stale/default text if the binding toggles before the modifier is rebuilt.
Consider making the modifier observe `SubscriptionHandler` and read
`handler.alertTitle`/`handler.alertMessage` at presentation time, or pass these fields through
bindings as well.

-        alertTitle: handler.alertTitle,
-        alertMessage: handler.alertMessage,
+        alertTitle: Binding(
+          get: { handler.alertTitle },
+          set: { handler.alertTitle = $0 }
+        ),
+        alertMessage: Binding(
+          get: { handler.alertMessage },
+          set: { handler.alertMessage = $0 }
+        ),


─── MoviePilot-TV/Views/Components/SubscriptionModifier.swift:39-40 ───
This appends `SubscribeSeasonRequest` into the supplied `NavigationPath`, but the current codebase
has no `navigationDestination(for: SubscribeSeasonRequest.self)` registration. On tvOS this will
leave the route unhandled (typically a runtime warning/no visible navigation) when a multi-season
subscription is requested. Ensure the modifier is only attached inside a `NavigationStack` that
registers a destination for `SubscribeSeasonRequest`, or move the destination registration into the
reusable subscription flow.
```
