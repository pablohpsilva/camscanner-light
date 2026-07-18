/// A purchasable tip, plugin-free so the domain and tests never depend on
/// `in_app_purchase`. [price] is the StoreKit-localized display string (e.g.
/// "$1.99", "1,99 €") — never a hardcoded amount.
class TipProduct {
  const TipProduct({required this.id, required this.price});

  final String id;
  final String price;
}
