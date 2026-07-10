import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/theme/ream_colors.dart';

import '../../support/ream_pump.dart';

void main() {
  testWidgets('donation-banner key is present', (tester) async {
    await pumpReam(tester, const DonationBanner());
    expect(find.byKey(const Key('donation-banner')), findsOneWidget);
  });

  testWidgets('banner background is amberSoft', (tester) async {
    await pumpReam(tester, const DonationBanner());

    // The Material widget wrapping the banner carries the background color.
    final material = tester.widget<Material>(
      find
          .ancestor(
            of: find.byKey(const Key('donation-banner')),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.color, ReamColors.light.amberSoft);
  });

  testWidgets('banner has amber top border', (tester) async {
    await pumpReam(tester, const DonationBanner());

    // Find the Container that has the BoxDecoration with the amber border.
    Container? decoratedContainer;
    tester
        .widgetList<Container>(
          find.ancestor(
            of: find.byKey(const Key('donation-banner')),
            matching: find.byType(Container),
          ),
        )
        .forEach((c) {
          if (c.decoration is BoxDecoration) decoratedContainer = c;
        });

    expect(decoratedContainer, isNotNull);
    final border =
        (decoratedContainer!.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, ReamColors.light.amber);
  });

  testWidgets('banner copy text uses ink2 color', (tester) async {
    await pumpReam(tester, const DonationBanner());

    final text = tester.widget<Text>(find.textContaining('support').first);
    expect(text.style?.color, ReamColors.light.ink2);
  });

  testWidgets('banner shows a heart icon and a trailing chevron', (
    tester,
  ) async {
    await pumpReam(tester, const DonationBanner());

    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });
}
