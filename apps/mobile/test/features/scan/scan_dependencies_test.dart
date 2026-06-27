import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/camera_permission_service_impl.dart';
import 'package:mobile/features/scan/camera_preview_controller_impl.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';

void main() {
  test('production ScanDependencies wires the plugin-backed implementations',
      () {
    const deps = ScanDependencies();
    expect(deps.createPermissionService(),
        isA<PermissionHandlerCameraPermissionService>());
    expect(deps.createPreviewController(),
        isA<PluginCameraPreviewController>());
  });
}
