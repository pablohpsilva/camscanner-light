import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('shareExtraMenuItems', () {
    testWidgets('includes Share link + Fax by default with prefixed keys', (
      tester,
    ) async {
      final items = shareExtraMenuItems(showFax: true, keyPrefix: 'p');
      expect(items.length, 2);
      expect((items[0] as PopupMenuItem).value, kShareLinkValue);
      expect((items[1] as PopupMenuItem).value, kFaxValue);
      expect(items[0].key, const Key('p-share-link'));
      expect(items[1].key, const Key('p-fax'));
    });

    testWidgets('omits Fax when showFax is false', (tester) async {
      final items = shareExtraMenuItems(showFax: false, keyPrefix: 'p');
      expect(items.length, 1);
      expect((items[0] as PopupMenuItem).value, kShareLinkValue);
    });
  });

  group('ShareMenuButton', () {
    testWidgets('Share item invokes onShare', (tester) async {
      var shared = 0;
      await tester.pumpWidget(
        _host(
          ShareMenuButton(buttonKey: const Key('btn'), onShare: () => shared++),
        ),
      );
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-share')));
      await tester.pumpAndSettle();
      expect(shared, 1);
    });

    testWidgets('Fax while unavailable shows SnackBar, does not call onShare', (
      tester,
    ) async {
      var shared = 0;
      await tester.pumpWidget(
        _host(
          ShareMenuButton(buttonKey: const Key('btn'), onShare: () => shared++),
        ),
      );
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-fax')));
      await tester.pumpAndSettle();
      expect(find.text(kFaxUnavailableMessage), findsOneWidget);
      expect(shared, 0);
    });

    testWidgets('Share link while unavailable shows SnackBar', (tester) async {
      await tester.pumpWidget(
        _host(ShareMenuButton(buttonKey: const Key('btn'), onShare: () {})),
      );
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-share-link')));
      await tester.pumpAndSettle();
      expect(find.text(kLinkShareUnavailableMessage), findsOneWidget);
    });

    testWidgets('showFax:false hides the Fax item', (tester) async {
      await tester.pumpWidget(
        _host(
          ShareMenuButton(
            buttonKey: const Key('btn'),
            onShare: () {},
            showFax: false,
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-menu-fax')), findsNothing);
      expect(find.byKey(const Key('share-menu-share-link')), findsOneWidget);
    });
  });
}
