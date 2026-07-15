// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Luxembourgish Letzeburgesch (`lb`).
class AppLocalizationsLb extends AppLocalizations {
  AppLocalizationsLb([String locale = 'lb']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Ofbriechen';

  @override
  String get commonSave => 'Späicheren';

  @override
  String get commonDelete => 'Läschen';

  @override
  String get commonRetry => 'Nach eng Kéier';

  @override
  String get commonRetake => 'Nei ophuelen';

  @override
  String get commonShare => 'Deelen';

  @override
  String get commonRename => 'Ëmbenennen';

  @override
  String get commonCopied => 'Kopéiert';

  @override
  String get commonDocumentOptions => 'Dokumentoptiounen';

  @override
  String get commonSearchHint => 'Titelen a Text an de Säiten sichen';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Säiten',
      one: '1 Säit',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument =>
      'Dokument konnt net gespäichert ginn. Probéier nach eng Kéier.';

  @override
  String get commonErrorRename => 'Konnt net ëmbenannt ginn';

  @override
  String get commonErrorShare => 'Konnt net gedeelt ginn';

  @override
  String get homeDocumentsTitle => 'Dokumenter';

  @override
  String get homePrivateOnDevice => 'Privat · op dësem Apparat';

  @override
  String get homeCancelSelectionTooltip => 'Auswiel ofbriechen';

  @override
  String homeSelectedCount(int count) {
    return '$count ausgewielt';
  }

  @override
  String get homeExportTooltip => 'Exportéieren';

  @override
  String get homeActionScan => 'Scannen';

  @override
  String get homeActionIdCard => 'Perséinlechen Ausweis';

  @override
  String get homeActionImport => 'Importéieren';

  @override
  String homeSearchNoMatch(String query) {
    return 'Keen Dokument passt op \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments => 'Dokumenter konnten net gelueden ginn.';

  @override
  String get homeErrorImportPhoto => 'Foto konnt net importéiert ginn';

  @override
  String get homeViewList => 'Lëscht';

  @override
  String get homeViewGrid => 'Gitter';

  @override
  String get homeEmptyTitle => 'Nach keng Dokumenter';

  @override
  String get homeEmptySubtitle =>
      'Tipp op Scannen fir däin éischt Dokument z\'erstellen';

  @override
  String get sortName => 'Numm';

  @override
  String get sortCreated => 'Erstallt';

  @override
  String get sortModified => 'Geännert';

  @override
  String get settingsTitle => 'Astellungen';

  @override
  String get settingsSectionAppearance => 'Erscheinungsbild';

  @override
  String get settingsThemeLight => 'Hell';

  @override
  String get settingsThemeDark => 'Donkel';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsSectionLanguage => 'Sprooch';

  @override
  String get settingsLanguageSystem => 'Systemstandard';

  @override
  String get settingsSectionFeedback => 'Feedback & Ënnerstëtzung';

  @override
  String get settingsSupportApp => 'D\'App ënnerstëtzen';

  @override
  String get settingsAboutTagline =>
      'Deng Scannen bleiwen op dengem Apparat — kee Konto, keng Cloud.';

  @override
  String get donationHeadline => 'Keng Kontoen. Keng Cloud.\\nKeen Abonnement.';

  @override
  String get donationDisclaimer =>
      'Dëst ass just eng fräiwëlleg Spend. Du kriss doriwwer keng Funktiounen, Virdeeler oder Inhalter — et hëlleft einfach déi lafend Entwécklung z\'ënnerstëtzen.';

  @override
  String get donationOptionalNote =>
      'Spenden schalt näischt fräi — all Funktioun gehéiert der scho. Dëst ass wierklech fräiwëlleg.';

  @override
  String get donationKofiButton => 'Bezuel mir e Kaffi — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Ko-fi konnt net opgemaach ginn';

  @override
  String get donationBitcoinCopied => 'Bitcoin-Adress kopéiert';

  @override
  String get donationBitcoinHeading => 'Oder mat Bitcoin spenden';

  @override
  String get donationCopyAddress => 'Adress kopéieren';

  @override
  String get donationBannerText =>
      'Gefält der d\'App? Tipp fir se z\'ënnerstëtzen';

  @override
  String get scanTitle => 'Scannen';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Säiten gespäichert',
      one: '1 Säit gespäichert',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'Säit konnt net ersat ginn. Probéier nach eng Kéier.';

  @override
  String get scanSaveFailed => 'De Scan konnt net gespäichert ginn.';

  @override
  String get idScanTitle => 'Ausweis scannen';

  @override
  String get idScanFrontPrompt => 'Scann d\'VIRSÄIT vum Ausweis';

  @override
  String get idScanBackPrompt => 'Scann d\'RÉCKSÄIT vum Ausweis';

  @override
  String get idScanSaving => 'Gëtt gespäichert…';

  @override
  String get idScanErrorSave =>
      'Den Ausweis konnt net gespäichert ginn. Probéier nach eng Kéier.';

  @override
  String get idScanErrorBackRetake =>
      'D\'Virsäit ass gespäichert, mä d\'Récksäit huet net funktionéiert. Hëll se aus dem Dokument nei op.';

  @override
  String get captureReviewTitle => 'Iwwerpréiwen';

  @override
  String get captureReviewReset => 'Zerécksetzen';

  @override
  String get captureReviewAccept => 'Iwwerhuelen';

  @override
  String get editFilterTitle => 'Filter';

  @override
  String get editCropTitle => 'Iwwerpréiwen & botzen';

  @override
  String get filterAuto => 'Automatesch';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Faarf';

  @override
  String get filterGrayscale => 'Grotéin';

  @override
  String get toolbarCrop => 'Zoushneiden';

  @override
  String get toolbarRotate => 'Dréinen';

  @override
  String get toolbarFilter => 'Filter';

  @override
  String get toolbarText => 'Text';

  @override
  String get cropHandleTopEdge => 'Mëttelpunkt uewen';

  @override
  String get cropHandleRightEdge => 'Mëttelpunkt riets';

  @override
  String get cropHandleBottomEdge => 'Mëttelpunkt ënnen';

  @override
  String get cropHandleLeftEdge => 'Mëttelpunkt lénks';

  @override
  String get cropHandleTopLeft => 'Zoushneid-Eck uewen lénks';

  @override
  String get cropHandleTopRight => 'Zoushneid-Eck uewen riets';

  @override
  String get cropHandleBottomRight => 'Zoushneid-Eck ënnen riets';

  @override
  String get cropHandleBottomLeft => 'Zoushneid-Eck ënnen lénks';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Dëst Dokument läschen? Dat kann net réckgängeg gemaach ginn.';

  @override
  String get viewerDeleteDocumentError => 'Konnt net geläscht ginn';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Dat ass déi eenzeg Säit. Wann s de se läschs, gëtt dat ganzt Dokument geläscht.';

  @override
  String get viewerDeletePageConfirm =>
      'Dës Säit läschen? Dat kann net réckgängeg gemaach ginn.';

  @override
  String get viewerDeletePageError => 'Säit konnt net geläscht ginn';

  @override
  String get viewerExportPdfError => 'PDF konnt net exportéiert ginn';

  @override
  String get viewerShareImageError => 'Bild konnt net gedeelt ginn';

  @override
  String get viewerShareImagesError => 'Biller konnten net gedeelt ginn';

  @override
  String get viewerPrintSuccess => 'Un den Drécker geschéckt';

  @override
  String get viewerPrintError => 'Konnt net gedréckt ginn';

  @override
  String get viewerProtectPdfSuccess => 'Geschützt PDF ass prett';

  @override
  String get viewerProtectPdfError => 'PDF konnt net geschützt ginn';

  @override
  String get viewerSplitLastPageWarning =>
      'Dat ass déi lescht Säit — et gëtt näischt fir duerno opzedeelen.';

  @override
  String get viewerSplitSuccess => 'An en neit Dokument opgedeelt';

  @override
  String get viewerSplitError => 'Konnt net opgedeelt ginn';

  @override
  String get viewerMergeError => 'Konnt net zesummegefouert ginn';

  @override
  String get viewerReorderPagesError => 'Säiten konnten net nei geuerdent ginn';

  @override
  String get viewerRotateError => 'Konnt net gedréint ginn';

  @override
  String get viewerCropError => 'Zoushnëtt konnt net aktualiséiert ginn';

  @override
  String get viewerFilterError => 'Filter konnt net geännert ginn';

  @override
  String get viewerLoadError => 'Dëst Dokument konnt net gelueden ginn.';

  @override
  String get viewerEmptyPages => 'Dëst Dokument huet keng Säiten.';

  @override
  String get viewerMenuMerge => 'En anert Dokument zesummeféieren…';

  @override
  String get viewerMenuSplit => 'No dëser Säit opdeelen';

  @override
  String get viewerMenuDeleteDocument => 'Dokument läschen';

  @override
  String get viewerShareExportPdf => 'PDF exportéieren';

  @override
  String get viewerShareAsImage => 'Als Bild deelen';

  @override
  String get viewerShareAllAsImages => 'Alles als Biller deelen';

  @override
  String get viewerSharePrint => 'Drécken';

  @override
  String get viewerShareProtect => 'Mat Passwuert schützen';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Link deelen';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable => 'Link-Deelen ass nach net verfügbar';

  @override
  String get shareFaxUnavailable => 'Fax ass nach net verfügbar';

  @override
  String get renameDialogTitle => 'Dokument ëmbenennen';

  @override
  String get renameFieldLabel => 'Numm';

  @override
  String get passwordDialogTitle => 'PDF mat Passwuert schützen';

  @override
  String get passwordFieldHint => 'Passwuert aginn';

  @override
  String get passwordProtectButton => 'Schützen';

  @override
  String get exportQualityTitle => 'Exportqualitéit';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Voll Qualitéit, gréisst Datei';

  @override
  String get exportQualityHigh => 'Héich';

  @override
  String get exportQualityHighDesc => 'Héich Qualitéit';

  @override
  String get exportQualityMedium => 'Mëttel';

  @override
  String get exportQualityMediumDesc => 'Gutt fir E-Mail';

  @override
  String get exportQualityLow => 'Niddreg';

  @override
  String get exportQualityLowDesc => 'Klengst Datei';

  @override
  String get mergeDialogTitle => 'En anert Dokument zesummeféieren';

  @override
  String get mergeDialogEmpty => 'Keng aner Dokumenter fir zesummenzeféieren.';

  @override
  String get ocrTitle => 'Erkannten Text';

  @override
  String get ocrErrorRecognize => 'Text konnt net erkannt ginn';

  @override
  String get ocrErrorExport => 'Text konnt net exportéiert ginn';

  @override
  String get ocrTextLayerReady => 'Textschicht prett · dréit d\'Sich';

  @override
  String get ocrCopyText => 'Text kopéieren';

  @override
  String get ocrShareTxt => '.txt deelen';

  @override
  String get ocrEmpty => 'Op dëser Säit gouf nach kee Text erkannt.';

  @override
  String get ocrRecognizeButton => 'Text erkennen';

  @override
  String get pdfPreviewOpenError => 'D\'PDF konnt net opgemaach ginn.';

  @override
  String get feedbackTitle => 'Feedback schécken';

  @override
  String get feedbackSuccess => 'Merci! Däi Feedback gouf geschéckt.';

  @override
  String get feedbackRateLimited =>
      'Du hues der scho puer geschéckt — probéier w.e.g. méi spéit nach eng Kéier.';

  @override
  String get feedbackRejectedUnverified =>
      'D\'App konnt net verifizéiert ginn — probéier w.e.g. nach eng Kéier.';

  @override
  String get feedbackOffline =>
      'Iwwerpréif deng Verbindung a probéier nach eng Kéier.';

  @override
  String get feedbackInvalid =>
      'Iwwerpréif w.e.g. deng Noriicht a probéier nach eng Kéier.';

  @override
  String get feedbackServerError =>
      'Konnt elo net geschéckt ginn — probéier w.e.g. nach eng Kéier.';

  @override
  String get feedbackTypeLabel => 'Zort';

  @override
  String get feedbackTypeBug => 'Feeler';

  @override
  String get feedbackTypeIdea => 'Iddi';

  @override
  String get feedbackTypeQuestion => 'Fro';

  @override
  String get feedbackMessageLabel => 'Noriicht';

  @override
  String get feedbackMessageHint => 'Däi Feedback';

  @override
  String get feedbackMessageRequired => 'Gëff w.e.g. eng Noriicht an';

  @override
  String get feedbackEmailLabel => 'E-Mail — fräiwëlleg';

  @override
  String get feedbackEmailHint => 'du@beispill.com';

  @override
  String get feedbackEmailInvalid =>
      'Gëff eng gülteg E-Mail an oder looss et eidel';

  @override
  String get feedbackEmailPublicNote =>
      'Fräiwëlleg. Dëst gëtt op GitHub ëffentlech siichtbar.';

  @override
  String get feedbackDiagnosticsShow => 'Wat gëtt geschéckt?';

  @override
  String get feedbackDiagnosticsHide => 'Verstopp wat geschéckt gëtt';

  @override
  String get feedbackDiagnosticsTitle => 'Wat mir mateschécken';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnosdate matgeschéckt: App-Versioun, OS-Versioun, Apparatmodell a Sprooch. Et gi ni gescannten Dokumenter oder hiren Inhalt geschéckt.';

  @override
  String get feedbackSubmit => 'Bericht schécken';
}
