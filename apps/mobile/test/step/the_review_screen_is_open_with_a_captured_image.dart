import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../test/support/fake_library.dart';

/// Shared repo instance — set by the Given step; read by the Then steps.
FakeDocumentRepository g1Repo = FakeDocumentRepository();

/// Usage: the review screen is open with a captured image
Future<void> theReviewScreenIsOpenWithACapturedImage(
    WidgetTester tester) async {
  g1Repo = FakeDocumentRepository();
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g1bdd.jpg'),
      saving: false,
      onRetake: () {},
      // Record the enhancer that CameraScreen would pass to SaveController.
      onAccept: (CropCorners corners, ImageEnhancer enhancer) {
        g1Repo.lastSavedEnhancer = enhancer;
      },
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List(0),
    ),
  ));
  await tester.pumpAndSettle();
}
