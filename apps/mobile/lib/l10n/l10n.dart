import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

/// Ergonomic accessor: `context.l10n.homeDocumentsTitle`.
extension AppL10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}
