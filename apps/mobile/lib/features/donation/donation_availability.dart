import 'package:flutter/foundation.dart';

/// Whether the EXTERNAL donation options (Ko-fi link + Bitcoin) may be shown.
///
/// App Store guideline 3.1.1: donations to the developer must go through
/// In-App Purchase on iOS/iPadOS, so the external Ko-fi/Bitcoin body is
/// Android-only. iOS uses the IAP tip jar instead (see [tipJarAvailable]).
bool get donationsAvailable => defaultTargetPlatform != TargetPlatform.iOS;

/// Whether the store-compliant IAP tip jar may be shown. iOS-only: on iOS the
/// only compliant "give money, get nothing back" path is consumable IAP.
bool get tipJarAvailable => defaultTargetPlatform == TargetPlatform.iOS;

/// Whether ANY donation entry point (home banner + Settings "Support the app"
/// row) should be visible. Both platforms now have a compliant path, so both
/// show an entry point; the destination screen picks the right body.
bool get donationEntryPointsAvailable => donationsAvailable || tipJarAvailable;
