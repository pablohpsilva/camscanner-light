import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_product_ids.dart';

void main() {
  test('exactly the three consumable tip product ids in ascending order', () {
    expect(kTipProductIds, ['tip_small', 'tip_medium', 'tip_large']);
  });
}
