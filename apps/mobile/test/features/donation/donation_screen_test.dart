import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {required String kofiUrl, required String bitcoinAddress}) async {
    await tester.pumpWidget(MaterialApp(
      home: DonationScreen(kofiUrl: kofiUrl, bitcoinAddress: bitcoinAddress),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('always shows the no-benefits disclaimer', (tester) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(
      find.textContaining('no features, benefits, or content'),
      findsOneWidget,
    );
  });

  testWidgets('hides Ko-fi and Bitcoin sections when unconfigured',
      (tester) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
  });

  testWidgets('shows Ko-fi button and Bitcoin section when configured',
      (tester) async {
    await pump(tester,
        kofiUrl: 'https://ko-fi.com/example',
        bitcoinAddress: 'bc1qexampleaddress');
    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsOneWidget);
    expect(find.text('bc1qexampleaddress'), findsOneWidget);
  });

  testWidgets('copy button writes the Bitcoin address to the clipboard',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform,
        (MethodCall call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester,
        kofiUrl: '', bitcoinAddress: 'bc1qexampleaddress');
    await tester.ensureVisible(find.byKey(const Key('donation-bitcoin-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('donation-bitcoin-copy')));
    await tester.pumpAndSettle();

    final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map)['text'], 'bc1qexampleaddress');
  });
}
