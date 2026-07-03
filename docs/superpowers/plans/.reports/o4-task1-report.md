# O4 Task 1 Report — `exportRecognizedText` repository method

## Status: DONE

## Commit

`58056ad` — feat(o4): exportRecognizedText — cached OCR text to a temp .txt

## Files Changed

- `apps/mobile/lib/features/library/document_repository.dart` — added `exportRecognizedText` interface method (with doc comment)
- `apps/mobile/lib/features/library/drift/drift_document_repository.dart` — DRY-extracted `_exportBaseName`; `_pdfFileNameFor` now delegates to it; added `exportRecognizedText` implementation
- `apps/mobile/test/support/fake_library.dart` — added `throwOnExportText` flag, `lastExportedTextPosition` recorder, and `exportRecognizedText` method
- `apps/mobile/test/features/library/export_recognized_text_test.dart` — new test file (3 tests)

## Test Run Output

### Red run (Step 2 — before implementation)

```
00:00 +0: loading .../export_recognized_text_test.dart
test/features/library/export_recognized_text_test.dart:50:29: Error: The method 'exportRecognizedText' isn't defined for the type 'DriftDocumentRepository'.
...
00:00 +0 -1: Some tests failed.
```

### Green run (Step 6 — after implementation)

```
00:00 +0: loading .../export_recognized_text_test.dart
00:00 +0: writes a temp .txt with the cached text and a sanitized name
00:00 +1: throws when the page has no recognized text
00:00 +2: throws when the page row does not exist
00:00 +3: All tests passed!
```

## Flutter Analyze Output

```
Analyzing mobile...
No issues found! (ran in 3.6s)
```

## Implementation Notes

- `_pdfFileNameFor` was refactored to call the new `_exportBaseName` helper — DRY, zero behavior change.
- `exportRecognizedText` writes to `Directory.systemTemp.createTemp('txt_export')` — never under the document base dir.
- Throws `DocumentExportException` (not `DocumentSaveException`) for both "no page" and "no text" cases, matching the plan.
- The `const` constructor on the `DocumentExportException('exportText failed: no recognized text')` throw was kept to match the plan's intent.
- Fake implementation writes a real temp file so tests that assert `file.exists()` would pass too.
