import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/save_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

void main() {
  const img = CapturedImage('/tmp/cap.jpg');

  test('save() toggles saving and returns the document on success', () async {
    final repo = FakeDocumentRepository();
    final c = SaveController(repository: repo);
    final states = <SaveStatus>[];
    c.addListener(() => states.add(c.status));

    final doc = await c.save(img);

    expect(doc, isNotNull);
    expect(repo.createCalls, 1);
    expect(c.status, SaveStatus.idle);
    expect(states, containsAllInOrder([SaveStatus.saving, SaveStatus.idle]));
  });

  test('save() goes to error and returns null on failure', () async {
    final c = SaveController(repository: FakeDocumentRepository(throwOnCreate: true));
    final doc = await c.save(img);
    expect(doc, isNull);
    expect(c.status, SaveStatus.error);
  });

  test('a second save while one is in flight is ignored', () async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(gate: gate);
    final c = SaveController(repository: repo);

    final first = c.save(img);
    final second = await c.save(img); // in-flight → ignored
    expect(second, isNull);
    expect(repo.createCalls, 1);

    gate.complete();
    expect(await first, isNotNull);
    expect(c.saving, isFalse);
  });

  test('disposing mid-save does not notify after dispose', () async {
    final gate = Completer<void>();
    final c = SaveController(repository: FakeDocumentRepository(gate: gate));
    var notifications = 0;
    c.addListener(() => notifications++);

    // ignore: unawaited_futures
    c.save(img);
    await Future<void>.value();
    final at = notifications;
    c.dispose();
    gate.complete();
    await Future<void>.value();
    expect(notifications, at, reason: 'no notifyListeners() after dispose');
  });

  test('save() threads the enhancer to the repository', () async {
    final repo = FakeDocumentRepository();
    final c = SaveController(repository: repo);
    await c.save(
      const CapturedImage('/tmp/cap.jpg'),
      enhancer: const GrayscaleEnhancer(),
    );
    expect(repo.lastSavedEnhancer, isA<GrayscaleEnhancer>());
    c.dispose();
  });
}
