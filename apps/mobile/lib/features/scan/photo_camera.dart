import 'package:image_picker/image_picker.dart';

import 'captured_image.dart';

/// Captures a single photo from the device camera. Injectable (DIP) so widget
/// and BDD tests use a fake instead of the platform camera. Parallel to
/// [GalleryPicker].
abstract interface class PhotoCamera {
  /// Returns the captured photo as a [CapturedImage], or null if the user
  /// cancelled. Never throws.
  Future<CapturedImage?> capture();
}

/// Production camera backed by image_picker. One shot per call on both
/// platforms — nothing leaves the device. Thin adapter (not host-testable — the
/// native camera UI is out of Flutter's reach); the flow is tested through
/// [PhotoCamera] with a fake.
class ImagePickerPhotoCamera implements PhotoCamera {
  const ImagePickerPhotoCamera();
  @override
  Future<CapturedImage?> capture() async {
    final x = await ImagePicker().pickImage(source: ImageSource.camera);
    return x == null ? null : CapturedImage(x.path);
  }
}
