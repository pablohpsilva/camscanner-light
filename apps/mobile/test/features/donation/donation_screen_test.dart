import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:url_launcher_platform_interface/link.dart';
import 'package:url_launcher_platform_interface/url_launcher_platform_interface.dart';

class _MockUrlLauncher extends Fake
    with MockPlatformInterfaceMixin
    implements UrlLauncherPlatform {
  PreferredLaunchMode? capturedMode;
  String? capturedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    capturedUrl = url;
    capturedMode = options.mode;
    return true;
  }

  @override
  Future<bool> canLaunch(String url) async => true;

  @override
  Future<bool> supportsMode(PreferredLaunchMode mode) async => true;

  @override
  Future<bool> supportsCloseForMode(PreferredLaunchMode mode) async => true;
}

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required String kofiUrl,
    required String bitcoinAddress,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DonationScreen(kofiUrl: kofiUrl, bitcoinAddress: bitcoinAddress),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('always shows the no-benefits disclaimer', (tester) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(
      find.textContaining('no features, benefits, or content'),
      findsOneWidget,
    );
  });

  testWidgets('hides Ko-fi and Bitcoin sections when unconfigured', (
    tester,
  ) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
  });

  testWidgets('shows Ko-fi button and Bitcoin section when configured', (
    tester,
  ) async {
    await pump(
      tester,
      kofiUrl: 'https://ko-fi.com/example',
      bitcoinAddress: 'bc1qexampleaddress',
    );
    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsOneWidget);
    expect(find.text('bc1qexampleaddress'), findsOneWidget);
  });

  testWidgets('copy button writes the Bitcoin address to the clipboard', (
    tester,
  ) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (
      MethodCall call,
    ) async {
      calls.add(call);
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pump(tester, kofiUrl: '', bitcoinAddress: 'bc1qexampleaddress');
    await tester.ensureVisible(find.byKey(const Key('donation-bitcoin-copy')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('donation-bitcoin-copy')));
    await tester.pumpAndSettle();

    final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map)['text'], 'bc1qexampleaddress');
  });

  testWidgets('Ko-fi button opens URL in the external browser', (tester) async {
    final mock = _MockUrlLauncher();
    final original = UrlLauncherPlatform.instance;
    UrlLauncherPlatform.instance = mock;
    addTearDown(() => UrlLauncherPlatform.instance = original);

    await pump(
      tester,
      kofiUrl: 'https://ko-fi.com/example',
      bitcoinAddress: '',
    );
    await tester.tap(find.byKey(const Key('donation-kofi-button')));
    await tester.pumpAndSettle();

    expect(mock.capturedMode, PreferredLaunchMode.externalApplication);
    expect(mock.capturedUrl, 'https://ko-fi.com/example');
  });

  testWidgets('donation uses Ream chrome (header + paper bg)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: const DonationScreen(
          kofiUrl: 'https://ko-fi.com/x',
          bitcoinAddress: 'bc1qtest',
        ),
      ),
    );
    expect(find.text('Support the app'), findsOneWidget);
    expect(find.textContaining('Ream'), findsNothing);
    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, ReamColors.light.paper);
  });
}
