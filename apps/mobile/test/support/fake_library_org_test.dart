import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import 'fake_library.dart';

void main() {
  test('fake folders: create/list/move/delete-to-unfiled', () async {
    final repo = FakeDocumentRepository();
    final f = await repo.createFolder('Receipts');
    expect((await repo.listFolders()).single.id, f.id);

    final doc = Document(
      id: 1,
      name: 'D',
      createdAt: DateTime.utc(2026, 6, 27),
      modifiedAt: DateTime.utc(2026, 6, 27),
    );
    repo.documents.add(doc);
    await repo.moveToFolder(doc.id, f.id);
    expect((await repo.listDocumentSummaries()).single.folderId, f.id);

    await repo.deleteFolder(f.id);
    expect(await repo.listFolders(), isEmpty);
    expect((await repo.listDocumentSummaries()).single.folderId, isNull);
  });

  test('fake tags: create dedupes, setDocumentTags, enrichment', () async {
    final repo = FakeDocumentRepository();
    final t1 = await repo.createTag('Tax');
    final t2 = await repo.createTag('tax'); // dedupe
    expect(t2.id, t1.id);

    final doc = Document(
      id: 1,
      name: 'D',
      createdAt: DateTime.utc(2026, 6, 27),
      modifiedAt: DateTime.utc(2026, 6, 27),
    );
    repo.documents.add(doc);
    await repo.setDocumentTags(doc.id, {t1.id});
    expect((await repo.listDocumentSummaries()).single.tags.single.name, 'Tax');
  });
}
