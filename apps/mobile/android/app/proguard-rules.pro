# --- S1 R8 keep rules ---------------------------------------------------------
# R8 is enabled to shrink the Java/Kotlin dex + resources. These rules keep the
# reflection/JNI entry points R8 cannot see and silence optional classes that
# are referenced but intentionally NOT bundled.

# Flutter embedding (flutter ships consumer rules; explicit for safety).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# ML Kit text recognition: the Latin recognizer is bundled; the plugin also
# references optional CJK/Devanagari/Japanese/Korean recognizers that are NOT
# bundled (Latin-only build). Keep the ML Kit + GMS surface and silence the
# missing optional classes so R8 neither fails on them nor strips the Latin OCR
# path. (This is the exact failure the old build.gradle comment warned about.)
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.mlkit.**
-dontwarn com.google.android.gms.**

# Flutter plugin implementations reached via registration/reflection
# (pdfx, printing, share_plus, sqlite3/drift, cunning_document_scanner, …).
-keep class io.flutter.plugins.** { *; }
-dontwarn io.flutter.plugins.**

# cunning_document_scanner (OS document scanner) transitively pulls Huawei HMS
# ML/network libs. Their network layer references optional Cronet
# (org.chromium.net) and Conscrypt classes that are NOT bundled on our
# Google-services build path, so R8 full-mode aborts on the missing references.
# Silence them (and the HMS surface) — unreachable on-device via Google services.
-dontwarn org.chromium.net.**
-dontwarn org.conscrypt.**
-dontwarn com.huawei.hms.**
# Huawei's secure-encrypt util references BouncyCastle crypto that is not bundled.
-dontwarn org.bouncycastle.**
