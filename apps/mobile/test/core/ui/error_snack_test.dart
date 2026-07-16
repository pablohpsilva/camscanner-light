import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/ui/error_snack.dart';

void main() {
  testWidgets('showErrorSnack shows a SnackBar with the message', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    ctx.showErrorSnack('Something failed');
    await tester.pump(); // let the SnackBar appear

    expect(find.widgetWithText(SnackBar, 'Something failed'), findsOneWidget);
  });
}
