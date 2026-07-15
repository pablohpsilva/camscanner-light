import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import 'export_quality.dart';

/// Shows the export-quality picker and resolves to the chosen [ExportQuality]
/// (or null if cancelled/dismissed). A dialog, matching the app's other pickers.
Future<ExportQuality?> showExportQualityDialog(BuildContext context) {
  return showDialog<ExportQuality>(
    context: context,
    builder: (_) => const ExportQualityDialog(),
  );
}

class ExportQualityDialog extends StatelessWidget {
  const ExportQualityDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      key: const Key('export-quality-dialog'),
      title: Text(l10n.exportQualityTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final q in ExportQuality.values)
              ListTile(
                key: Key('export-quality-${q.name}'),
                title: Text(q.label(l10n)),
                subtitle: Text(q.description(l10n)),
                onTap: () => Navigator.of(context).pop(q),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('export-quality-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
      ],
    );
  }
}
