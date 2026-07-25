import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/theme/app_theme.dart';
import 'package:mobile/theme/widgets/app_back_header.dart';

SystemUiOverlayStyle _overlayOf(WidgetTester t) => t
    .widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.descendant(
        of: find.byType(AppBackHeader),
        matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
      ),
    )
    .value;

void main() {
  testWidgets('light theme → dark status-bar icons', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(appBar: AppBackHeader(title: 'X')),
      ),
    );
    expect(_overlayOf(t).statusBarIconBrightness, Brightness.dark);
  });

  testWidgets('dark theme → light status-bar icons', (t) async {
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: const Scaffold(appBar: AppBackHeader(title: 'X')),
      ),
    );
    expect(_overlayOf(t).statusBarIconBrightness, Brightness.light);
  });
}
