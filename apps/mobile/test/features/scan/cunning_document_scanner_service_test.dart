import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/cunning_document_scanner_service.dart';

void main() {
  test('maps returned paths to CapturedImage in order', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => ['/a.jpg', '/b.jpg'],
    );
    final pages = await service.scan();
    expect(pages.map((p) => p.path).toList(), ['/a.jpg', '/b.jpg']);
  });

  test('null result (cancel) → empty list', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => null,
    );
    expect(await service.scan(), isEmpty);
  });

  test('launcher throwing → empty list (never throws)', () async {
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async => throw Exception('boom'),
    );
    expect(await service.scan(), isEmpty);
  });

  test('pageLimit is forwarded as noOfPages', () async {
    int? seen;
    final service = CunningDocumentScannerService(
      launch: ({int? noOfPages}) async {
        seen = noOfPages;
        return const <String>[];
      },
    );
    await service.scan(pageLimit: 1);
    expect(seen, 1);
  });
}
