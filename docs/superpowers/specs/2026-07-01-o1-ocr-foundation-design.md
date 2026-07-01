# O1 OCR Page-Text Foundation — Design Spec

**Date:** 2026-07-01
**Step:** O1 — OCR foundation (Feature 08 / OCR, Sub-project 2, first slice)
**Status:** Approved
**Depends on:** B1–B3 (pages persisted), G-series (enhanced images) — gated
**Feeds:** O2 (real OCR engine + auto-run), O3 (searchable-PDF text layer via the existing `PdfTextLayer` seam), O4 (copy/export text), content-search (Feature 02)

---

## Goal

Establish the **engine-agnostic OCR data + persistence foundation**: a page can be
run through an `OcrEngine` (DIP) and have its recognized **text + word bounding
boxes cached on the page**, retrievable for later slices. This is the walking
skeleton every OCR capability plugs into — the searchable-PDF layer (O3), text
export (O4), and content search all consume this cached data.

**Nothing leaves the device**: OCR is local; the pipeline is pure Dart around a
DIP engine.

---

## Scope & the deferred engine decision

Spec 08 names an engine ("Tesseract with downloadable language packs"). That is a
**consequential, hard-to-reverse architectural choice** (app footprint vs
language breadth vs native complexity) that also has an efficiency/UX alternative
(ML Kit: bundled on-device models, simpler, but larger base app). **O1 deliberately
does NOT pick an engine.** It ships:

- The `OcrEngine` **interface** (DIP) — the seam any engine implements.
- `NoOpOcrEngine` — the production default for O1 (recognizes nothing; the
  pipeline exists but produces empty results until a real engine lands).
- `FakeOcrEngine` — test double returning fixed text + boxes.

The real engine (ML Kit vs Tesseract) is **O2's** decision, made with its own
design phase and — because it contradicts the spec's stated engine and commits
the sub-project's direction — a user checkpoint. O1 needs no engine commitment;
its value is the architecture + persistence, provable on-device with the fake.

**O1 also excludes** (later slices): automatic background OCR after save (O2, with
the real engine, where isolate/threading is designed for that engine); language
detection/packs (O5); code-aware handling (O6); the PDF text layer (O3); text
export (O4); content-search index. **YAGNI** for O1.

---

## Architecture

| Layer | Change |
|---|---|
| `ocr/ocr_result.dart` (new) | `OcrResult` (text + word boxes) + `OcrWordBox`, with JSON (de)serialization |
| `ocr/ocr_engine.dart` (new) | `OcrEngine` interface + `NoOpOcrEngine` |
| `fake_library.dart` (test support) | `FakeOcrEngine` |
| `drift/app_database.dart` | Pages: `ocrText` + `ocrBoxes` nullable columns; `schemaVersion` 3→4 + migration |
| `DriftDocumentRepository` | Inject `OcrEngine`; `Future<void> runOcr(documentId, position)` recognizes + caches; `getDocumentPages` exposes `ocrText` |
| `PageImage` | Add `final String? ocrText` |
| `LibraryDependencies` / `tempLibraryDependencies` | Wire `ocrEngine` (prod `NoOp`; OCR tests/BDD inject `FakeOcrEngine`) |

New files live under `apps/mobile/lib/features/library/ocr/` (a focused, single-
responsibility folder for the OCR seam).

---

## Components

### `OcrResult` + `OcrWordBox` (`ocr/ocr_result.dart`)

```dart
/// One recognized word and its box, normalized to the page image (0..1).
class OcrWordBox {
  final String text;
  final double left, top, right, bottom; // normalized [0,1]
  const OcrWordBox({
    required this.text,
    required this.left, required this.top,
    required this.right, required this.bottom,
  });
  Map<String, dynamic> toJson() => {
        't': text, 'l': left, 'o': top, 'r': right, 'b': bottom,
      };
  factory OcrWordBox.fromJson(Map<String, dynamic> j) => OcrWordBox(
        text: j['t'] as String,
        left: (j['l'] as num).toDouble(), top: (j['o'] as num).toDouble(),
        right: (j['r'] as num).toDouble(), bottom: (j['b'] as num).toDouble(),
      );
}

/// A page's recognized text and word boxes. [text] is the full recognized text;
/// [words] are the per-word boxes (used by the invisible PDF layer in O3).
class OcrResult {
  final String text;
  final List<OcrWordBox> words;
  const OcrResult({required this.text, this.words = const []});
  static const empty = OcrResult(text: '', words: []);

  String encodeBoxes() => jsonEncode(words.map((w) => w.toJson()).toList());
  static List<OcrWordBox> decodeBoxes(String? json) {
    if (json == null || json.isEmpty) return const [];
    final list = jsonDecode(json) as List;
    return list
        .map((e) => OcrWordBox.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
```

### `OcrEngine` interface + `NoOpOcrEngine` (`ocr/ocr_engine.dart`)

```dart
/// Recognizes text in an image. Injectable (DIP) — the real on-device engine
/// (ML Kit / Tesseract) is chosen in O2; O1 ships only NoOp + a test fake.
/// Implementations do their heavy work off the UI thread (their own concern).
abstract interface class OcrEngine {
  /// Recognizes text in [imageBytes] (a JPEG). Returns [OcrResult.empty] when
  /// there is no text. Must not throw for a valid-but-textless image.
  Future<OcrResult> recognize(Uint8List imageBytes);
}

/// O1 production default: recognizes nothing. The pipeline exists; a real engine
/// (O2) replaces this without touching callers.
class NoOpOcrEngine implements OcrEngine {
  const NoOpOcrEngine();
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async => OcrResult.empty;
}
```

### `FakeOcrEngine` (test support)

Returns a fixed non-empty result so tests can assert caching + retrieval:

```dart
class FakeOcrEngine implements OcrEngine {
  final OcrResult result;
  const FakeOcrEngine([this.result = const OcrResult(
      text: 'HELLO WORLD',
      words: [OcrWordBox(text: 'HELLO', left: .1, top: .1, right: .4, bottom: .2),
              OcrWordBox(text: 'WORLD', left: .5, top: .1, right: .9, bottom: .2)])]);
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async => result;
}
```

---

## Persistence

Pages gains two nullable columns (derived data, non-destructive, re-runnable):

```dart
/// Recognized OCR text for this page (O1); null until OCR has run.
TextColumn get ocrText => text().nullable()();
/// JSON-encoded word boxes (OcrResult.encodeBoxes); null until OCR has run.
TextColumn get ocrBoxes => text().nullable()();
```

`schemaVersion` 3 → **4**; migration adds both columns:

```dart
if (from < 4) {
  await m.addColumn(pages, pages.ocrText);
  await m.addColumn(pages, pages.ocrBoxes);
}
```

`app_database.g.dart` is regenerated via `dart run build_runner build
--delete-conflicting-outputs` (drift codegen) and committed. A migration test
(v3 → v4 adds the columns; a fresh write round-trips) follows the existing
`migration_test.dart` pattern.

---

## Repository

`DriftDocumentRepository` gains an injected engine (default `NoOpOcrEngine`):

```dart
final OcrEngine _ocrEngine; // ctor param: OcrEngine ocrEngine = const NoOpOcrEngine()
```

New method:

```dart
/// Recognizes the page at [position] of [documentId] via the OCR engine and
/// caches the text + word boxes on the page row. Reads the page's DISPLAY image
/// (flat derivative if present, else original). A no-text result stores an empty
/// string (distinguishable from null = "not yet run"). Throws
/// [DocumentSaveException] when the page row is missing.
Future<void> runOcr(int documentId, int position);
```

Implementation: fetch the row (missing → `DocumentSaveException`); read
`flatRelativePath ?? relativeImagePath` bytes; `final r = await
_ocrEngine.recognize(bytes)`; `UPDATE pages SET ocrText = r.text, ocrBoxes =
r.encodeBoxes() WHERE id = row.id`. No transaction needed (single-row update).

`getDocumentPages` maps `ocrText` onto `PageImage.ocrText` (retrieval for later
slices). `PageImage` gains `final String? ocrText` (default null; existing
`const PageImage(...)` call sites keep compiling).

**Automatic-after-save is O2** — O1 exposes `runOcr` as the explicit capability so
it is deterministically testable; O2 wires the background trigger with the real
engine.

---

## Error handling

| Failure | Behavior |
|---|---|
| Page row missing | `runOcr` throws `DocumentSaveException` |
| Image file unreadable | the `readAsBytes` IO error propagates (caller decides) — O1 does not swallow; O2's background trigger will guard it |
| Engine returns empty (no text) | `ocrText = ''`, `ocrBoxes = '[]'` cached (valid "ran, found nothing") |

---

## Testing (acceptance mapping — O1's subset of spec 08)

Spec-08 criteria O1 advances: *the OCR seam/pipeline exists and caches text+boxes
per page on-device; no data leaves the device (pure local + DIP).* (Automatic
background run, languages, code-aware, PDF layer, export, search → later slices.)

**Unit — `OcrResult`** (`ocr_result_test.dart`): boxes round-trip through
`encodeBoxes`/`decodeBoxes`; `decodeBoxes(null)`/`('')` → empty; `empty` is text
`''` + no words.

**Unit — Drift** (`ocr_run_test.dart`, `NativeDatabase.memory()`):
- `runOcr` with `FakeOcrEngine` → page's `ocrText == 'HELLO WORLD'` and `ocrBoxes`
  decodes to 2 boxes.
- `runOcr` with `NoOpOcrEngine` → `ocrText == ''` (ran, found nothing), not null.
- `runOcr` on a missing position → throws `DocumentSaveException`.
- `getDocumentPages` exposes `ocrText` on `PageImage` after `runOcr`.
- Uses the **flat** image when present (seed a flat, assert the engine received it
  — via a recording fake that captures the bytes' length / a sentinel).

**Unit — migration** (`ocr_migration_test.dart`, mirrors `migration_test.dart`):
v3 schema upgraded to v4 gains `ocrText`/`ocrBoxes`; a fresh write round-trips.

**On-device integration** (`o1_ocr_test.dart`, real device): build a document on
the device's real SQLite + file store, `runOcr` with a `FakeOcrEngine`, and assert
the page's `ocrText` round-trips through the real DB. (No Gherkin/UI — O1 has no
user-facing surface; this is the authoritative on-device gate that the persistence
+ pipeline work on the Samsung, mirroring the E4 on-device integration test.)

**Verify harness — `scripts/verify/o1.sh`** (mirrors `i2.sh`): static asserts
(`OcrEngine` + `NoOpOcrEngine`, `OcrResult`, `runOcr` in drift repo, `ocrText`
column, on-device test file), host suite green, analyze clean, on-device
integration test.

---

## Out of Scope (YAGNI — later O-slices)

- Any real OCR engine / native dependency (O2).
- Automatic background OCR after save (O2).
- Language detection, multi-language, downloadable packs (O5).
- Code/symbol-aware recognition (O6).
- Searchable-PDF text layer (O3, via the existing `PdfTextLayer` seam).
- Copy/export `.txt`, selectable text view (O4).
- Content-search index (Feature 02).
