// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonRetake => 'Reprendre';

  @override
  String get commonShare => 'Partager';

  @override
  String get commonRename => 'Renommer';

  @override
  String get commonCopied => 'Copié';

  @override
  String get commonDocumentOptions => 'Options du document';

  @override
  String get commonSearchHint =>
      'Rechercher un titre ou un texte dans les pages';

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
  String get commonErrorSaveDocument =>
      'Impossible d\'enregistrer le document. Réessayez.';

  @override
  String get commonErrorRename => 'Impossible de renommer';

  @override
  String get commonErrorShare => 'Impossible de partager';

  @override
  String get homeDocumentsTitle => 'Documents';

  @override
  String get homePrivateOnDevice => 'Privé · sur cet appareil';

  @override
  String get homeCancelSelectionTooltip => 'Annuler la sélection';

  @override
  String homeSelectedCount(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get homeExportTooltip => 'Exporter';

  @override
  String get homeActionScan => 'Scanner';

  @override
  String get homeActionIdCard => 'Carte d\'identité';

  @override
  String get homeActionImport => 'Importer';

  @override
  String homeSearchNoMatch(String query) {
    return 'Aucun document ne correspond à « $query ».';
  }

  @override
  String get homeErrorLoadDocuments => 'Impossible de charger les documents.';

  @override
  String get homeErrorImportPhoto => 'Impossible d\'importer la photo';

  @override
  String get homeViewList => 'Liste';

  @override
  String get homeViewGrid => 'Grille';

  @override
  String get homeEmptyTitle => 'Aucun document pour l\'instant';

  @override
  String get homeEmptySubtitle =>
      'Appuyez sur Scanner pour créer votre premier document';

  @override
  String get sortName => 'Nom';

  @override
  String get sortCreated => 'Créé le';

  @override
  String get sortModified => 'Modifié le';

  @override
  String get settingsTitle => 'Réglages';

  @override
  String get settingsSectionAppearance => 'Apparence';

  @override
  String get settingsThemeLight => 'Clair';

  @override
  String get settingsThemeDark => 'Sombre';

  @override
  String get settingsThemeSystem => 'Système';

  @override
  String get settingsSectionLanguage => 'Langue';

  @override
  String get settingsLanguageSystem => 'Langue du système';

  @override
  String get settingsSectionFeedback => 'Retours & assistance';

  @override
  String get settingsSupportApp => 'Soutenir l\'application';

  @override
  String get settingsAboutTagline =>
      'Vos scans restent sur votre appareil — pas de compte, pas de cloud.';

  @override
  String get donationHeadline =>
      'Pas de compte. Pas de cloud.\nPas d\'abonnement.';

  @override
  String get donationDisclaimer =>
      'Ceci est un don volontaire uniquement. Vous ne recevez aucune fonctionnalité, avantage ou contenu en retour — cela aide simplement à soutenir le développement continu.';

  @override
  String get donationOptionalNote =>
      'Faire un don ne débloque rien : toutes les fonctionnalités sont déjà à vous. C\'est vraiment facultatif.';

  @override
  String get donationKofiButton => 'Offrez-moi un café — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Impossible d\'ouvrir Ko-fi';

  @override
  String get donationBitcoinCopied => 'Adresse Bitcoin copiée';

  @override
  String get donationBitcoinHeading => 'Ou faites un don en Bitcoin';

  @override
  String get donationCopyAddress => 'Copier l\'adresse';

  @override
  String get donationBannerText =>
      'Vous aimez l\'application ? Appuyez pour la soutenir';

  @override
  String donationTipButtonLabel(String price) {
    return 'Pourboire $price';
  }

  @override
  String get donationTipThankYouTitle => 'Merci ❤️';

  @override
  String get donationTipThankYouBody =>
      'Votre soutien fait vivre cette application.';

  @override
  String get donationTipThankYouClose => 'Fermer';

  @override
  String get donationTipUnavailable =>
      'Les pourboires ne sont pas disponibles pour le moment. Réessayez plus tard.';

  @override
  String get donationTipError => 'Impossible de finaliser le pourboire';

  @override
  String get scanTitle => 'Scanner';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages enregistrées',
      one: '1 page enregistrée',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'Impossible de remplacer la page. Réessayez.';

  @override
  String get scanSaveFailed => 'Impossible d\'enregistrer le scan.';

  @override
  String get idScanTitle => 'Scanner une pièce d\'identité';

  @override
  String get idScanFrontPrompt => 'Scannez le RECTO de la pièce d\'identité';

  @override
  String get idScanBackPrompt => 'Scannez le VERSO de la pièce d\'identité';

  @override
  String get idScanSaving => 'Enregistrement…';

  @override
  String get idScanErrorSave =>
      'Impossible d\'enregistrer la pièce d\'identité. Réessayez.';

  @override
  String get idScanErrorBackRetake =>
      'Le recto a été enregistré, mais le verso a échoué. Reprenez-le depuis le document.';

  @override
  String get captureReviewTitle => 'Vérification';

  @override
  String get captureReviewReset => 'Réinitialiser';

  @override
  String get captureReviewAccept => 'Accepter';

  @override
  String get editFilterTitle => 'Filtre';

  @override
  String get editCropTitle => 'Vérifier et nettoyer';

  @override
  String get filterAuto => 'Auto';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Couleur';

  @override
  String get filterGrayscale => 'Niveaux de gris';

  @override
  String get toolbarCrop => 'Recadrer';

  @override
  String get toolbarRotate => 'Pivoter';

  @override
  String get toolbarFilter => 'Filtre';

  @override
  String get toolbarText => 'Texte';

  @override
  String get cropHandleTopEdge => 'Milieu du bord supérieur';

  @override
  String get cropHandleRightEdge => 'Milieu du bord droit';

  @override
  String get cropHandleBottomEdge => 'Milieu du bord inférieur';

  @override
  String get cropHandleLeftEdge => 'Milieu du bord gauche';

  @override
  String get cropHandleTopLeft => 'Coin de recadrage supérieur gauche';

  @override
  String get cropHandleTopRight => 'Coin de recadrage supérieur droit';

  @override
  String get cropHandleBottomRight => 'Coin de recadrage inférieur droit';

  @override
  String get cropHandleBottomLeft => 'Coin de recadrage inférieur gauche';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Supprimer ce document ? Cette action est irréversible.';

  @override
  String get viewerDeleteDocumentError => 'Impossible de supprimer';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'C\'est la seule page. La supprimer supprime tout le document.';

  @override
  String get viewerDeletePageConfirm =>
      'Supprimer cette page ? Cette action est irréversible.';

  @override
  String get viewerDeletePageError => 'Impossible de supprimer la page';

  @override
  String get viewerExportPdfError => 'Impossible d\'exporter le PDF';

  @override
  String get viewerShareImageError => 'Impossible de partager l\'image';

  @override
  String get viewerShareImagesError => 'Impossible de partager les images';

  @override
  String get viewerPrintSuccess => 'Envoyé à l\'imprimante';

  @override
  String get viewerPrintError => 'Impossible d\'imprimer';

  @override
  String get viewerProtectPdfSuccess => 'PDF protégé prêt';

  @override
  String get viewerProtectPdfError => 'Impossible de protéger le PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'C\'est la dernière page — rien à diviser après.';

  @override
  String get viewerSplitSuccess => 'Divisé en un nouveau document';

  @override
  String get viewerSplitError => 'Impossible de diviser';

  @override
  String get viewerMergeError => 'Impossible de fusionner';

  @override
  String get viewerReorderPagesError => 'Impossible de réorganiser les pages';

  @override
  String get viewerRotateError => 'Impossible de pivoter';

  @override
  String get viewerCropError => 'Impossible de mettre à jour le recadrage';

  @override
  String get viewerFilterError => 'Impossible de changer le filtre';

  @override
  String get viewerLoadError => 'Impossible de charger ce document.';

  @override
  String get viewerEmptyPages => 'Ce document n\'a aucune page.';

  @override
  String get viewerMenuMerge => 'Fusionner un autre document…';

  @override
  String get viewerMenuSplit => 'Diviser après cette page';

  @override
  String get viewerMenuDeleteDocument => 'Supprimer le document';

  @override
  String get viewerShareExportPdf => 'Exporter en PDF';

  @override
  String get viewerShareAsImage => 'Partager comme image';

  @override
  String get viewerShareAllAsImages => 'Partager tout comme images';

  @override
  String get viewerSharePrint => 'Imprimer';

  @override
  String get viewerShareProtect => 'Protéger avec un mot de passe';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Partager le lien';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable =>
      'Le partage de lien n\'est pas encore disponible';

  @override
  String get shareFaxUnavailable => 'Le fax n\'est pas encore disponible';

  @override
  String get renameDialogTitle => 'Renommer le document';

  @override
  String get renameFieldLabel => 'Nom';

  @override
  String get passwordDialogTitle => 'Protéger le PDF par mot de passe';

  @override
  String get passwordFieldHint => 'Entrez un mot de passe';

  @override
  String get passwordProtectButton => 'Protéger';

  @override
  String get exportQualityTitle => 'Qualité d\'export';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc =>
      'Qualité maximale, fichier le plus volumineux';

  @override
  String get exportQualityHigh => 'Élevée';

  @override
  String get exportQualityHighDesc => 'Haute qualité';

  @override
  String get exportQualityMedium => 'Moyenne';

  @override
  String get exportQualityMediumDesc => 'Idéal pour l\'email';

  @override
  String get exportQualityLow => 'Faible';

  @override
  String get exportQualityLowDesc => 'Fichier le plus léger';

  @override
  String get mergeDialogTitle => 'Fusionner un autre document';

  @override
  String get mergeDialogEmpty => 'Aucun autre document à fusionner.';

  @override
  String get ocrTitle => 'Texte reconnu';

  @override
  String get ocrErrorRecognize => 'Impossible de reconnaître le texte';

  @override
  String get ocrErrorExport => 'Impossible d\'exporter le texte';

  @override
  String get ocrTextLayerReady =>
      'Couche de texte prête · alimente la recherche';

  @override
  String get ocrCopyText => 'Copier le texte';

  @override
  String get ocrShareTxt => 'Partager .txt';

  @override
  String get ocrEmpty => 'Aucun texte reconnu sur cette page pour l\'instant.';

  @override
  String get ocrRecognizeButton => 'Reconnaître le texte';

  @override
  String get pdfPreviewOpenError => 'Impossible d\'ouvrir le PDF.';

  @override
  String get feedbackTitle => 'Envoyer un commentaire';

  @override
  String get feedbackSuccess => 'Merci ! Votre commentaire a été envoyé.';

  @override
  String get feedbackRateLimited =>
      'Vous en avez déjà envoyé plusieurs — merci de réessayer plus tard.';

  @override
  String get feedbackRejectedUnverified =>
      'Impossible de vérifier l\'application — veuillez réessayer.';

  @override
  String get feedbackOffline => 'Vérifiez votre connexion et réessayez.';

  @override
  String get feedbackInvalid => 'Veuillez vérifier votre message et réessayer.';

  @override
  String get feedbackServerError =>
      'Impossible d\'envoyer pour le moment — veuillez réessayer.';

  @override
  String get feedbackTypeLabel => 'Type';

  @override
  String get feedbackTypeBug => 'Bug';

  @override
  String get feedbackTypeIdea => 'Idée';

  @override
  String get feedbackTypeQuestion => 'Question';

  @override
  String get feedbackMessageLabel => 'Message';

  @override
  String get feedbackMessageHint => 'Votre commentaire';

  @override
  String get feedbackMessageRequired => 'Veuillez saisir un message';

  @override
  String get feedbackEmailLabel => 'Email — facultatif';

  @override
  String get feedbackEmailHint => 'vous@exemple.com';

  @override
  String get feedbackEmailInvalid =>
      'Saisissez un email valide ou laissez le champ vide';

  @override
  String get feedbackEmailPublicNote =>
      'Facultatif. Ceci sera visible publiquement sur GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'Qu\'est-ce qui sera envoyé ?';

  @override
  String get feedbackDiagnosticsHide => 'Masquer ce qui sera envoyé';

  @override
  String get feedbackDiagnosticsTitle => 'Ce que nous incluons';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnostics joints : version de l\'application, version du système, modèle de l\'appareil et langue. Aucun document scanné ni son contenu n\'est jamais envoyé.';

  @override
  String get feedbackSubmit => 'Envoyer le rapport';
}
