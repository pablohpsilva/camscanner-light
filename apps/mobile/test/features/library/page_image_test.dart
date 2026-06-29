import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';

void main() {
  group('PageImage.displayPath', () {
    test('returns imagePath when flatImagePath is null', () {
      const page = PageImage(position: 1, imagePath: '/orig/page_1.jpg');
      expect(page.displayPath, '/orig/page_1.jpg');
    });

    test('returns flatImagePath when set', () {
      const page = PageImage(
        position: 1,
        imagePath: '/orig/page_1.jpg',
        flatImagePath: '/orig/page_1_flat.jpg',
      );
      expect(page.displayPath, '/orig/page_1_flat.jpg');
    });

    test('flatImagePath defaults to null', () {
      const page = PageImage(position: 1, imagePath: '/x.jpg');
      expect(page.flatImagePath, isNull);
    });
  });
}
