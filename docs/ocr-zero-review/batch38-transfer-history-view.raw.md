```text
[ocr] Summary: 1 file(s) reviewed, 1 comment(s), ~485510 token(s) used (input: ~478683, output: ~6827), cache(read: ~210944, write: ~0), 6m20s elapsed

─── MoviePilot-TV/Views/Pages/TransferHistoryView.swift:248-248 ───
When an AI redo is already running, this keeps the action enabled for the row that is currently
pending. In single-item mode the view model filters it out, but in batch mode a selection that
includes this pending row plus other rows can still call `triggerAiRedo`; that method cancels the
previous `aiRedoTask`, which can leave the earlier accepted id in `aiRedoingIds` indefinitely and
desynchronize the progress state. Prefer disabling the AI redo action while any redo task is active,
or otherwise prevent starting a new batch without cancelling/cleaning up the previous one.

-           isEnabled: !viewModel.isAiRedoing || isSingleItemPending,
+           isEnabled: !viewModel.isAiRedoing,
```
