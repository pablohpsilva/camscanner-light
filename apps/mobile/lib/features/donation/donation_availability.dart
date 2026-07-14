import 'package:flutter/foundation.dart';

/// Whether donation entry points may be shown on this platform.
///
/// App Store guideline 3.1.1: donations to the developer must go through
/// In-App Purchase on iOS/iPadOS, so every donation entry point (the
/// home-screen banner and the Settings "Support the app" row) is hidden
/// there. Android keeps the Ko-fi / Bitcoin options.
bool get donationsAvailable => defaultTargetPlatform != TargetPlatform.iOS;
