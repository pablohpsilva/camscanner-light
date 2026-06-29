import 'package:flutter/material.dart';

/// Shown when the device has no usable camera, or it failed to initialize.
class CameraUnavailableView extends StatelessWidget {
  const CameraUnavailableView({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_off_outlined, size: 64),
            SizedBox(height: 16),
            Text(
              'Camera unavailable on this device',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
