// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonSave => 'Save';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRetake => 'Retake';

  @override
  String get commonShare => 'Share';

  @override
  String get commonRename => 'Rename';

  @override
  String get commonCopied => 'Copied';

  @override
  String get commonDocumentOptions => 'Document options';

  @override
  String get commonSearchHint => 'Search titles & text inside pages';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument => 'Couldn\'t save document. Try again.';

  @override
  String get commonErrorRename => 'Couldn\'t rename';

  @override
  String get commonErrorShare => 'Couldn\'t share';

  @override
  String get homeDocumentsTitle => 'Documents';

  @override
  String get homePrivateOnDevice => 'Private · on this device';

  @override
  String get homeCancelSelectionTooltip => 'Cancel selection';

  @override
  String homeSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get homeExportTooltip => 'Export';

  @override
  String get homeActionScan => 'Scan';

  @override
  String get homeActionIdCard => 'ID card';

  @override
  String get homeActionImport => 'Import';

  @override
  String homeSearchNoMatch(String query) {
    return 'No documents match \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments => 'Couldn\'t load documents.';

  @override
  String get homeErrorImportPhoto => 'Couldn\'t import photo';

  @override
  String get homeViewList => 'List';

  @override
  String get homeViewGrid => 'Grid';

  @override
  String get homeEmptyTitle => 'No documents yet';

  @override
  String get homeEmptySubtitle => 'Tap Scan to create your first document';

  @override
  String get sortName => 'Name';

  @override
  String get sortCreated => 'Created';

  @override
  String get sortModified => 'Modified';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsLanguageSystem => 'System default';

  @override
  String get settingsSectionFeedback => 'Feedback & support';

  @override
  String get settingsSupportApp => 'Support the app';

  @override
  String get settingsAboutTagline =>
      'Your scans stay on your device — no account, no cloud.';

  @override
  String get donationHeadline => 'No accounts. No cloud.\\nNo subscription.';

  @override
  String get donationDisclaimer =>
      'This is a voluntary donation only. You receive no features, benefits, or content in return — it simply helps support ongoing development.';

  @override
  String get donationOptionalNote =>
      'Donating unlocks nothing — every feature is already yours. This is genuinely optional.';

  @override
  String get donationKofiButton => 'Buy me a coffee — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Couldn\'t open Ko-fi';

  @override
  String get donationBitcoinCopied => 'Bitcoin address copied';

  @override
  String get donationBitcoinHeading => 'Or donate with Bitcoin';

  @override
  String get donationCopyAddress => 'Copy address';

  @override
  String get donationBannerText => 'Enjoying the app? Tap to support it';

  @override
  String get scanTitle => 'Scan';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages saved',
      one: '1 page saved',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage => 'Couldn\'t replace page. Try again.';

  @override
  String get scanSaveFailed => 'Couldn\'t save the scan.';

  @override
  String get idScanTitle => 'Scan ID';

  @override
  String get idScanFrontPrompt => 'Scan the FRONT of the ID';

  @override
  String get idScanBackPrompt => 'Scan the BACK of the ID';

  @override
  String get idScanSaving => 'Saving…';

  @override
  String get idScanErrorSave => 'Couldn\'t save the ID. Try again.';

  @override
  String get idScanErrorBackRetake =>
      'Saved the front, but the back failed. Retake it from the document.';

  @override
  String get captureReviewTitle => 'Review';

  @override
  String get captureReviewReset => 'Reset';

  @override
  String get captureReviewAccept => 'Accept';

  @override
  String get editFilterTitle => 'Filter';

  @override
  String get editCropTitle => 'Review & clean';

  @override
  String get filterAuto => 'Auto';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Color';

  @override
  String get filterGrayscale => 'Grayscale';

  @override
  String get toolbarCrop => 'Crop';

  @override
  String get toolbarRotate => 'Rotate';

  @override
  String get toolbarFilter => 'Filter';

  @override
  String get toolbarText => 'Text';

  @override
  String get cropHandleTopEdge => 'Top edge midpoint';

  @override
  String get cropHandleRightEdge => 'Right edge midpoint';

  @override
  String get cropHandleBottomEdge => 'Bottom edge midpoint';

  @override
  String get cropHandleLeftEdge => 'Left edge midpoint';

  @override
  String get cropHandleTopLeft => 'Top-left crop corner';

  @override
  String get cropHandleTopRight => 'Top-right crop corner';

  @override
  String get cropHandleBottomRight => 'Bottom-right crop corner';

  @override
  String get cropHandleBottomLeft => 'Bottom-left crop corner';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Delete this document? This can\'t be undone.';

  @override
  String get viewerDeleteDocumentError => 'Couldn\'t delete';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'This is the only page. Deleting it removes the whole document.';

  @override
  String get viewerDeletePageConfirm =>
      'Delete this page? This can\'t be undone.';

  @override
  String get viewerDeletePageError => 'Couldn\'t delete page';

  @override
  String get viewerExportPdfError => 'Couldn\'t export PDF';

  @override
  String get viewerShareImageError => 'Couldn\'t share image';

  @override
  String get viewerShareImagesError => 'Couldn\'t share images';

  @override
  String get viewerPrintSuccess => 'Sent to printer';

  @override
  String get viewerPrintError => 'Couldn\'t print';

  @override
  String get viewerProtectPdfSuccess => 'Protected PDF ready';

  @override
  String get viewerProtectPdfError => 'Couldn\'t protect PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'This is the last page — nothing to split after.';

  @override
  String get viewerSplitSuccess => 'Split into a new document';

  @override
  String get viewerSplitError => 'Couldn\'t split';

  @override
  String get viewerMergeError => 'Couldn\'t merge';

  @override
  String get viewerReorderPagesError => 'Couldn\'t reorder pages';

  @override
  String get viewerRotateError => 'Couldn\'t rotate';

  @override
  String get viewerCropError => 'Couldn\'t update crop';

  @override
  String get viewerFilterError => 'Couldn\'t change filter';

  @override
  String get viewerLoadError => 'Couldn\'t load this document.';

  @override
  String get viewerEmptyPages => 'This document has no pages.';

  @override
  String get viewerMenuMerge => 'Merge another document…';

  @override
  String get viewerMenuSplit => 'Split after this page';

  @override
  String get viewerMenuDeleteDocument => 'Delete document';

  @override
  String get viewerShareExportPdf => 'Export PDF';

  @override
  String get viewerShareAsImage => 'Share as image';

  @override
  String get viewerShareAllAsImages => 'Share all as images';

  @override
  String get viewerSharePrint => 'Print';

  @override
  String get viewerShareProtect => 'Protect with password';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Share link';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable => 'Link sharing isn\'t available yet';

  @override
  String get shareFaxUnavailable => 'Fax isn\'t available yet';

  @override
  String get renameDialogTitle => 'Rename document';

  @override
  String get renameFieldLabel => 'Name';

  @override
  String get passwordDialogTitle => 'Password-protect PDF';

  @override
  String get passwordFieldHint => 'Enter a password';

  @override
  String get passwordProtectButton => 'Protect';

  @override
  String get exportQualityTitle => 'Export quality';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Full quality, largest file';

  @override
  String get exportQualityHigh => 'High';

  @override
  String get exportQualityHighDesc => 'High quality';

  @override
  String get exportQualityMedium => 'Medium';

  @override
  String get exportQualityMediumDesc => 'Good for email';

  @override
  String get exportQualityLow => 'Low';

  @override
  String get exportQualityLowDesc => 'Smallest file';

  @override
  String get mergeDialogTitle => 'Merge another document';

  @override
  String get mergeDialogEmpty => 'No other documents to merge.';

  @override
  String get ocrTitle => 'Recognized text';

  @override
  String get ocrErrorRecognize => 'Couldn\'t recognize text';

  @override
  String get ocrErrorExport => 'Couldn\'t export text';

  @override
  String get ocrTextLayerReady => 'Text layer ready · powers search';

  @override
  String get ocrCopyText => 'Copy text';

  @override
  String get ocrShareTxt => 'Share .txt';

  @override
  String get ocrEmpty => 'No text recognized on this page yet.';

  @override
  String get ocrRecognizeButton => 'Recognize text';

  @override
  String get pdfPreviewOpenError => 'Couldn\'t open the PDF.';

  @override
  String get feedbackTitle => 'Send feedback';

  @override
  String get feedbackSuccess => 'Thanks! Your feedback was sent.';

  @override
  String get feedbackRateLimited =>
      'You\'ve sent a few already — please try again later.';

  @override
  String get feedbackRejectedUnverified =>
      'Couldn\'t verify the app — please try again.';

  @override
  String get feedbackOffline => 'Check your connection and try again.';

  @override
  String get feedbackInvalid => 'Please check your message and try again.';

  @override
  String get feedbackServerError =>
      'Couldn\'t send right now — please try again.';

  @override
  String get feedbackTypeLabel => 'Type';

  @override
  String get feedbackTypeBug => 'Bug';

  @override
  String get feedbackTypeIdea => 'Idea';

  @override
  String get feedbackTypeQuestion => 'Question';

  @override
  String get feedbackMessageLabel => 'Message';

  @override
  String get feedbackMessageHint => 'Your feedback';

  @override
  String get feedbackMessageRequired => 'Please enter a message';

  @override
  String get feedbackEmailLabel => 'Email — optional';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid => 'Enter a valid email or leave it blank';

  @override
  String get feedbackEmailPublicNote =>
      'Optional. This will be publicly visible on GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'What will be sent?';

  @override
  String get feedbackDiagnosticsHide => 'Hide what will be sent';

  @override
  String get feedbackDiagnosticsTitle => 'What we include';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnostics attached: app version, OS version, device model, and language. No scanned documents or their contents are ever sent.';

  @override
  String get feedbackSubmit => 'Send report';
}
