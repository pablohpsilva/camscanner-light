import 'package:image_picker/image_picker.dart';

import 'captured_image.dart';

/// Picks a single image from the device gallery. Injectable (DIP) so widget and
/// BDD tests use a fake instead of the platform picker.
abstract interface class GalleryPicker {
  /// Returns the picked image as a [CapturedImage], or null if the user cancelled.
  Future<CapturedImage?> pick();
}

/// Production picker backed by image_picker. Reads a local photo — nothing leaves
/// the device. Thin adapter (not automated-testable — the native gallery UI is out
/// of Flutter's reach); the flow is tested through [GalleryPicker] with a fake.
class ImagePickerGalleryPicker implements GalleryPicker {
  const ImagePickerGalleryPicker();
  @override
  Future<CapturedImage?> pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery);
    return x == null ? null : CapturedImage(x.path);
  }
}
