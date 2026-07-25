import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_text_gatherer.dart';
import 'package:mobile/features/library/page_image.dart';

import '../../support/fake_library.dart';

void main() {
  group('DocumentTextGatherer', () {
    test('concatenates page OCR text in page order', () async {
      final repo = FakeDocumentRepository(
        pages: const [
          PageImage(position: 1, imagePath: '/x/1.jpg', ocrText: 'first page'),
          PageImage(position: 2, imagePath: '/x/2.jpg', ocrText: 'second page'),
          PageImage(position: 3, imagePath: '/x/3.jpg', ocrText: 'third page'),
        ],
      );
      final gatherer = DocumentTextGatherer(repository: repo);

      final text = await gatherer.gather(1);

      expect(text, 'first page\n\nsecond page\n\nthird page');
    });

    test(
      'sorts by position before concatenating (out-of-order input)',
      () async {
        final repo = FakeDocumentRepository(
          pages: const [
            PageImage(position: 2, imagePath: '/x/2.jpg', ocrText: 'B'),
            PageImage(position: 1, imagePath: '/x/1.jpg', ocrText: 'A'),
          ],
        );
        final gatherer = DocumentTextGatherer(repository: repo);

        expect(await gatherer.gather(1), 'A\n\nB');
      },
    );

    test('skips pages with null / empty / whitespace-only text', () async {
      final repo = FakeDocumentRepository(
        pages: const [
          PageImage(position: 1, imagePath: '/x/1.jpg', ocrText: 'kept'),
          PageImage(position: 2, imagePath: '/x/2.jpg', ocrText: null),
          PageImage(position: 3, imagePath: '/x/3.jpg', ocrText: '   '),
          PageImage(position: 4, imagePath: '/x/4.jpg', ocrText: 'also kept'),
        ],
      );
      final gatherer = DocumentTextGatherer(repository: repo);

      expect(await gatherer.gather(1), 'kept\n\nalso kept');
    });

    test('returns an empty string when no page has recognized text', () async {
      final repo = FakeDocumentRepository(
        pages: const [
          PageImage(position: 1, imagePath: '/x/1.jpg'),
          PageImage(position: 2, imagePath: '/x/2.jpg', ocrText: ''),
        ],
      );
      final gatherer = DocumentTextGatherer(repository: repo);

      expect(await gatherer.gather(1), isEmpty);
    });
  });
}
