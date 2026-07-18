import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/error_snack.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/ream_colors.dart';
import '../../../theme/widgets/ream_action_button.dart';
import 'tip_event.dart';
import 'tip_jar_service.dart';
import 'tip_product.dart';

/// iOS tip-jar body: loads consumable products and drives purchases through a
/// [TipJarService]. Success shows a thank-you dialog; cancel is silent; error
/// shows a snackbar; an unavailable store shows a friendly message (no dead
/// buttons).
class TipJarBody extends StatefulWidget {
  const TipJarBody({super.key, required this.createService});

  final TipJarService Function() createService;

  @override
  State<TipJarBody> createState() => _TipJarBodyState();
}

enum _Phase { loading, ready, purchasing, unavailable }

class _TipJarBodyState extends State<TipJarBody> {
  late final TipJarService _service = widget.createService();
  StreamSubscription<TipEvent>? _sub;
  _Phase _phase = _Phase.loading;
  List<TipProduct> _products = const [];

  @override
  void initState() {
    super.initState();
    _sub = _service.events.listen(_onEvent);
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await _service.loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _phase = products.isEmpty ? _Phase.unavailable : _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.unavailable);
    }
  }

  void _onEvent(TipEvent event) {
    if (!mounted) return;
    switch (event) {
      case TipEventPending():
        setState(() => _phase = _Phase.purchasing);
      case TipEventSuccess():
        setState(() => _phase = _Phase.ready);
        _showThankYou();
      case TipEventCanceled():
        setState(() => _phase = _Phase.ready);
      case TipEventError():
        setState(() => _phase = _Phase.ready);
        context.showErrorSnack(context.l10n.donationTipError);
    }
  }

  Future<void> _buy(TipProduct product) async {
    setState(() => _phase = _Phase.purchasing);
    await _service.buy(product);
  }

  Future<void> _showThankYou() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tip-thank-you-dialog'),
        title: Text(context.l10n.donationTipThankYouTitle),
        content: Text(context.l10n.donationTipThankYouBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.donationTipThankYouClose),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.unavailable:
        return Padding(
          key: const Key('tip-unavailable'),
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.donationTipUnavailable,
            textAlign: TextAlign.center,
            style: TextStyle(color: r.ink2, height: 1.5),
          ),
        );
      case _Phase.ready:
      case _Phase.purchasing:
        final busy = _phase == _Phase.purchasing;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final product in _products) ...[
              ReamActionButton(
                key: Key('tip-button-${product.id}'),
                label: context.l10n.donationTipButtonLabel(product.price),
                icon: Icons.favorite,
                primary: true,
                fillColor: r.kofiRed,
                onPressed: busy ? null : () => _buy(product),
              ),
              const SizedBox(height: 11),
            ],
            if (busy) const CircularProgressIndicator(),
          ],
        );
    }
  }
}
