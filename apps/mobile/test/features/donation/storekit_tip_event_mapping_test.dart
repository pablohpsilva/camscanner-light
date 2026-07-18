import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/storekit_tip_jar_service.dart';

void main() {
  test('maps PurchaseStatus to TipEvent', () {
    expect(tipEventFromStatus(PurchaseStatus.pending), isA<TipEventPending>());
    expect(
      tipEventFromStatus(PurchaseStatus.purchased),
      isA<TipEventSuccess>(),
    );
    expect(tipEventFromStatus(PurchaseStatus.restored), isA<TipEventSuccess>());
    expect(
      tipEventFromStatus(PurchaseStatus.canceled),
      isA<TipEventCanceled>(),
    );
    expect(tipEventFromStatus(PurchaseStatus.error), isA<TipEventError>());
  });
}
