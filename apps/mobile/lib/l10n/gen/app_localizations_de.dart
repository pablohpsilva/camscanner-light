// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonRetake => 'Erneut aufnehmen';

  @override
  String get commonShare => 'Teilen';

  @override
  String get commonRename => 'Umbenennen';

  @override
  String get commonCopied => 'Kopiert';

  @override
  String get commonDocumentOptions => 'Dokumentoptionen';

  @override
  String get commonSearchHint => 'Titel & Text in Seiten durchsuchen';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten',
      one: '1 Seite',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument =>
      'Dokument konnte nicht gespeichert werden. Bitte erneut versuchen.';

  @override
  String get commonErrorRename => 'Umbenennen fehlgeschlagen';

  @override
  String get commonErrorShare => 'Teilen fehlgeschlagen';

  @override
  String get homeDocumentsTitle => 'Dokumente';

  @override
  String get homePrivateOnDevice => 'Privat · auf diesem Gerät';

  @override
  String get homeCancelSelectionTooltip => 'Auswahl aufheben';

  @override
  String homeSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get homeExportTooltip => 'Exportieren';

  @override
  String get homeActionScan => 'Scannen';

  @override
  String get homeActionIdCard => 'Ausweis';

  @override
  String get homeActionImport => 'Importieren';

  @override
  String homeSearchNoMatch(String query) {
    return 'Keine Dokumente gefunden für \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments =>
      'Dokumente konnten nicht geladen werden.';

  @override
  String get homeErrorImportPhoto => 'Foto konnte nicht importiert werden';

  @override
  String get homeViewList => 'Liste';

  @override
  String get homeViewGrid => 'Raster';

  @override
  String get homeEmptyTitle => 'Noch keine Dokumente';

  @override
  String get homeEmptySubtitle =>
      'Tippe auf Scannen, um dein erstes Dokument zu erstellen';

  @override
  String get sortName => 'Name';

  @override
  String get sortCreated => 'Erstellt';

  @override
  String get sortModified => 'Geändert';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsSectionAppearance => 'Erscheinungsbild';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Dunkel';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsSectionLanguage => 'Sprache';

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsSectionFeedback => 'Feedback & Support';

  @override
  String get settingsSupportApp => 'App unterstützen';

  @override
  String get settingsAboutTagline =>
      'Deine Scans bleiben auf deinem Gerät — kein Konto, keine Cloud.';

  @override
  String get donationHeadline => 'Keine Konten. Keine Cloud.\\nKein Abo.';

  @override
  String get donationDisclaimer =>
      'Dies ist eine freiwillige Spende. Du erhältst dafür keine Funktionen, Vorteile oder Inhalte — sie unterstützt lediglich die weitere Entwicklung.';

  @override
  String get donationOptionalNote =>
      'Eine Spende schaltet nichts frei — jede Funktion gehört dir bereits. Sie ist wirklich optional.';

  @override
  String get donationKofiButton => 'Spendier mir einen Kaffee — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Ko-fi konnte nicht geöffnet werden';

  @override
  String get donationBitcoinCopied => 'Bitcoin-Adresse kopiert';

  @override
  String get donationBitcoinHeading => 'Oder mit Bitcoin spenden';

  @override
  String get donationCopyAddress => 'Adresse kopieren';

  @override
  String get donationBannerText =>
      'Gefällt dir die App? Tippe, um sie zu unterstützen';

  @override
  String donationTipButtonLabel(String price) {
    return 'Trinkgeld $price';
  }

  @override
  String get donationTipThankYouTitle => 'Danke ❤️';

  @override
  String get donationTipThankYouBody =>
      'Deine Unterstützung hält diese App am Laufen.';

  @override
  String get donationTipThankYouClose => 'Schließen';

  @override
  String get donationTipUnavailable =>
      'Trinkgelder sind derzeit nicht verfügbar. Bitte versuche es später erneut.';

  @override
  String get donationTipError => 'Trinkgeld konnte nicht abgeschlossen werden';

  @override
  String get scanTitle => 'Scannen';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Seiten gespeichert',
      one: '1 Seite gespeichert',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'Seite konnte nicht ersetzt werden. Bitte erneut versuchen.';

  @override
  String get scanSaveFailed => 'Der Scan konnte nicht gespeichert werden.';

  @override
  String get idScanTitle => 'Ausweis scannen';

  @override
  String get idScanFrontPrompt => 'VORDERSEITE des Ausweises scannen';

  @override
  String get idScanBackPrompt => 'RÜCKSEITE des Ausweises scannen';

  @override
  String get idScanSaving => 'Wird gespeichert…';

  @override
  String get idScanErrorSave =>
      'Ausweis konnte nicht gespeichert werden. Bitte erneut versuchen.';

  @override
  String get idScanErrorBackRetake =>
      'Vorderseite gespeichert, aber Rückseite fehlgeschlagen. Bitte im Dokument erneut aufnehmen.';

  @override
  String get captureReviewTitle => 'Überprüfen';

  @override
  String get captureReviewReset => 'Zurücksetzen';

  @override
  String get captureReviewAccept => 'Übernehmen';

  @override
  String get editFilterTitle => 'Filter';

  @override
  String get editCropTitle => 'Prüfen & bereinigen';

  @override
  String get filterAuto => 'Auto';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Farbe';

  @override
  String get filterGrayscale => 'Graustufen';

  @override
  String get toolbarCrop => 'Zuschneiden';

  @override
  String get toolbarRotate => 'Drehen';

  @override
  String get toolbarFilter => 'Filter';

  @override
  String get toolbarText => 'Text';

  @override
  String get cropHandleTopEdge => 'Mittelpunkt obere Kante';

  @override
  String get cropHandleRightEdge => 'Mittelpunkt rechte Kante';

  @override
  String get cropHandleBottomEdge => 'Mittelpunkt untere Kante';

  @override
  String get cropHandleLeftEdge => 'Mittelpunkt linke Kante';

  @override
  String get cropHandleTopLeft => 'Zuschneideecke oben links';

  @override
  String get cropHandleTopRight => 'Zuschneideecke oben rechts';

  @override
  String get cropHandleBottomRight => 'Zuschneideecke unten rechts';

  @override
  String get cropHandleBottomLeft => 'Zuschneideecke unten links';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Dieses Dokument löschen? Das kann nicht rückgängig gemacht werden.';

  @override
  String get viewerDeleteDocumentError => 'Löschen fehlgeschlagen';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Dies ist die einzige Seite. Beim Löschen wird das gesamte Dokument entfernt.';

  @override
  String get viewerDeletePageConfirm =>
      'Diese Seite löschen? Das kann nicht rückgängig gemacht werden.';

  @override
  String get viewerDeletePageError => 'Seite konnte nicht gelöscht werden';

  @override
  String get viewerExportPdfError => 'PDF konnte nicht exportiert werden';

  @override
  String get viewerShareImageError => 'Bild konnte nicht geteilt werden';

  @override
  String get viewerShareImagesError => 'Bilder konnten nicht geteilt werden';

  @override
  String get viewerPrintSuccess => 'An Drucker gesendet';

  @override
  String get viewerPrintError => 'Drucken fehlgeschlagen';

  @override
  String get viewerProtectPdfSuccess => 'Geschützte PDF bereit';

  @override
  String get viewerProtectPdfError => 'PDF konnte nicht geschützt werden';

  @override
  String get viewerSplitLastPageWarning =>
      'Dies ist die letzte Seite — danach gibt es nichts mehr zu teilen.';

  @override
  String get viewerSplitSuccess => 'In neues Dokument aufgeteilt';

  @override
  String get viewerSplitError => 'Aufteilen fehlgeschlagen';

  @override
  String get viewerMergeError => 'Zusammenführen fehlgeschlagen';

  @override
  String get viewerReorderPagesError =>
      'Seiten konnten nicht neu angeordnet werden';

  @override
  String get viewerRotateError => 'Drehen fehlgeschlagen';

  @override
  String get viewerCropError => 'Zuschnitt konnte nicht aktualisiert werden';

  @override
  String get viewerFilterError => 'Filter konnte nicht geändert werden';

  @override
  String get viewerLoadError => 'Dieses Dokument konnte nicht geladen werden.';

  @override
  String get viewerEmptyPages => 'Dieses Dokument hat keine Seiten.';

  @override
  String get viewerMenuMerge => 'Anderes Dokument zusammenführen…';

  @override
  String get viewerMenuSplit => 'Nach dieser Seite teilen';

  @override
  String get viewerMenuDeleteDocument => 'Dokument löschen';

  @override
  String get viewerShareExportPdf => 'PDF exportieren';

  @override
  String get viewerShareAsImage => 'Als Bild teilen';

  @override
  String get viewerShareAllAsImages => 'Alle als Bilder teilen';

  @override
  String get viewerSharePrint => 'Drucken';

  @override
  String get viewerShareProtect => 'Mit Passwort schützen';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Link teilen';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable => 'Link-Teilen ist noch nicht verfügbar';

  @override
  String get shareFaxUnavailable => 'Fax ist noch nicht verfügbar';

  @override
  String get renameDialogTitle => 'Dokument umbenennen';

  @override
  String get renameFieldLabel => 'Name';

  @override
  String get passwordDialogTitle => 'PDF mit Passwort schützen';

  @override
  String get passwordFieldHint => 'Passwort eingeben';

  @override
  String get passwordProtectButton => 'Schützen';

  @override
  String get exportQualityTitle => 'Exportqualität';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Volle Qualität, größte Datei';

  @override
  String get exportQualityHigh => 'Hoch';

  @override
  String get exportQualityHighDesc => 'Hohe Qualität';

  @override
  String get exportQualityMedium => 'Mittel';

  @override
  String get exportQualityMediumDesc => 'Gut für E-Mail';

  @override
  String get exportQualityLow => 'Niedrig';

  @override
  String get exportQualityLowDesc => 'Kleinste Datei';

  @override
  String get mergeDialogTitle => 'Anderes Dokument zusammenführen';

  @override
  String get mergeDialogEmpty => 'Keine anderen Dokumente zum Zusammenführen.';

  @override
  String get ocrTitle => 'Erkannter Text';

  @override
  String get ocrErrorRecognize => 'Text konnte nicht erkannt werden';

  @override
  String get ocrErrorExport => 'Text konnte nicht exportiert werden';

  @override
  String get ocrTextLayerReady => 'Textebene bereit · unterstützt die Suche';

  @override
  String get ocrCopyText => 'Text kopieren';

  @override
  String get ocrShareTxt => '.txt teilen';

  @override
  String get ocrEmpty => 'Auf dieser Seite wurde noch kein Text erkannt.';

  @override
  String get ocrRecognizeButton => 'Text erkennen';

  @override
  String get pdfPreviewOpenError => 'Die PDF konnte nicht geöffnet werden.';

  @override
  String get feedbackTitle => 'Feedback senden';

  @override
  String get feedbackSuccess => 'Danke! Dein Feedback wurde gesendet.';

  @override
  String get feedbackRateLimited =>
      'Du hast bereits mehrere gesendet — bitte später erneut versuchen.';

  @override
  String get feedbackRejectedUnverified =>
      'Die App konnte nicht verifiziert werden — bitte erneut versuchen.';

  @override
  String get feedbackOffline => 'Bitte Verbindung prüfen und erneut versuchen.';

  @override
  String get feedbackInvalid => 'Bitte Nachricht prüfen und erneut versuchen.';

  @override
  String get feedbackServerError =>
      'Konnte gerade nicht gesendet werden — bitte erneut versuchen.';

  @override
  String get feedbackTypeLabel => 'Typ';

  @override
  String get feedbackTypeBug => 'Fehler';

  @override
  String get feedbackTypeIdea => 'Idee';

  @override
  String get feedbackTypeQuestion => 'Frage';

  @override
  String get feedbackMessageLabel => 'Nachricht';

  @override
  String get feedbackMessageHint => 'Dein Feedback';

  @override
  String get feedbackMessageRequired => 'Bitte eine Nachricht eingeben';

  @override
  String get feedbackEmailLabel => 'E-Mail — optional';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid => 'Gültige E-Mail eingeben oder leer lassen';

  @override
  String get feedbackEmailPublicNote =>
      'Optional. Dies wird auf GitHub öffentlich sichtbar sein.';

  @override
  String get feedbackDiagnosticsShow => 'Was wird gesendet?';

  @override
  String get feedbackDiagnosticsHide => 'Verbergen, was gesendet wird';

  @override
  String get feedbackDiagnosticsTitle => 'Was wir einschließen';

  @override
  String get feedbackDiagnosticsBody =>
      'Beigefügte Diagnosedaten: App-Version, Betriebssystemversion, Gerätemodell und Sprache. Gescannte Dokumente oder ihre Inhalte werden nie gesendet.';

  @override
  String get feedbackSubmit => 'Bericht senden';
}
