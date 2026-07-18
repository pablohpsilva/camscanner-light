// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'İptal';

  @override
  String get commonSave => 'Kaydet';

  @override
  String get commonDelete => 'Sil';

  @override
  String get commonRetry => 'Yeniden dene';

  @override
  String get commonRetake => 'Yeniden çek';

  @override
  String get commonShare => 'Paylaş';

  @override
  String get commonRename => 'Yeniden adlandır';

  @override
  String get commonCopied => 'Kopyalandı';

  @override
  String get commonDocumentOptions => 'Belge seçenekleri';

  @override
  String get commonSearchHint => 'Başlıklarda ve sayfa metinlerinde ara';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfa',
      one: '1 sayfa',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument => 'Belge kaydedilemedi. Tekrar deneyin.';

  @override
  String get commonErrorRename => 'Yeniden adlandırılamadı';

  @override
  String get commonErrorShare => 'Paylaşılamadı';

  @override
  String get homeDocumentsTitle => 'Belgeler';

  @override
  String get homePrivateOnDevice => 'Gizli · bu cihazda';

  @override
  String get homeCancelSelectionTooltip => 'Seçimi iptal et';

  @override
  String homeSelectedCount(int count) {
    return '$count seçildi';
  }

  @override
  String get homeExportTooltip => 'Dışa aktar';

  @override
  String get homeActionScan => 'Tara';

  @override
  String get homeActionIdCard => 'Kimlik kartı';

  @override
  String get homeActionImport => 'İçe aktar';

  @override
  String homeSearchNoMatch(String query) {
    return '\"$query\" ile eşleşen belge yok.';
  }

  @override
  String get homeErrorLoadDocuments => 'Belgeler yüklenemedi.';

  @override
  String get homeErrorImportPhoto => 'Fotoğraf içe aktarılamadı';

  @override
  String get homeViewList => 'Liste';

  @override
  String get homeViewGrid => 'Izgara';

  @override
  String get homeEmptyTitle => 'Henüz belge yok';

  @override
  String get homeEmptySubtitle => 'İlk belgeni oluşturmak için Tara\'ya dokun';

  @override
  String get sortName => 'Ad';

  @override
  String get sortCreated => 'Oluşturulma';

  @override
  String get sortModified => 'Değiştirilme';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get settingsSectionAppearance => 'Görünüm';

  @override
  String get settingsThemeLight => 'Açık';

  @override
  String get settingsThemeDark => 'Koyu';

  @override
  String get settingsThemeSystem => 'Sistem';

  @override
  String get settingsSectionLanguage => 'Dil';

  @override
  String get settingsLanguageSystem => 'Sistem varsayılanı';

  @override
  String get settingsSectionFeedback => 'Geri bildirim ve destek';

  @override
  String get settingsSupportApp => 'Uygulamayı destekle';

  @override
  String get settingsAboutTagline =>
      'Taramaların cihazında kalır — hesap yok, bulut yok.';

  @override
  String get donationHeadline => 'Hesap yok. Bulut yok.\\nAbonelik yok.';

  @override
  String get donationDisclaimer =>
      'Bu tamamen gönüllü bir bağıştır. Karşılığında herhangi bir özellik, ayrıcalık veya içerik almazsınız — yalnızca sürekli gelişime destek olur.';

  @override
  String get donationOptionalNote =>
      'Bağış hiçbir şeyin kilidini açmaz — tüm özellikler zaten senin. Bu gerçekten isteğe bağlı.';

  @override
  String get donationKofiButton => 'Bana bir kahve ısmarla — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Ko-fi açılamadı';

  @override
  String get donationBitcoinCopied => 'Bitcoin adresi kopyalandı';

  @override
  String get donationBitcoinHeading => 'Ya da Bitcoin ile bağışla';

  @override
  String get donationCopyAddress => 'Adresi kopyala';

  @override
  String get donationBannerText =>
      'Uygulamayı beğendin mi? Desteklemek için dokun';

  @override
  String donationTipButtonLabel(String price) {
    return 'Bahşiş $price';
  }

  @override
  String get donationTipThankYouTitle => 'Teşekkürler ❤️';

  @override
  String get donationTipThankYouBody =>
      'Desteğin bu uygulamayı ayakta tutuyor.';

  @override
  String get donationTipThankYouClose => 'Kapat';

  @override
  String get donationTipUnavailable =>
      'Bahşişler şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.';

  @override
  String get donationTipError => 'Bahşiş tamamlanamadı';

  @override
  String get scanTitle => 'Tara';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sayfa kaydedildi',
      one: '1 sayfa kaydedildi',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage => 'Sayfa değiştirilemedi. Tekrar deneyin.';

  @override
  String get scanSaveFailed => 'Tarama kaydedilemedi.';

  @override
  String get idScanTitle => 'Kimlik tara';

  @override
  String get idScanFrontPrompt => 'Kimliğin ÖN yüzünü tara';

  @override
  String get idScanBackPrompt => 'Kimliğin ARKA yüzünü tara';

  @override
  String get idScanSaving => 'Kaydediliyor…';

  @override
  String get idScanErrorSave => 'Kimlik kaydedilemedi. Tekrar deneyin.';

  @override
  String get idScanErrorBackRetake =>
      'Ön yüz kaydedildi, ancak arka yüz başarısız oldu. Belgeden yeniden çekin.';

  @override
  String get captureReviewTitle => 'İnceleme';

  @override
  String get captureReviewReset => 'Sıfırla';

  @override
  String get captureReviewAccept => 'Onayla';

  @override
  String get editFilterTitle => 'Filtre';

  @override
  String get editCropTitle => 'İncele ve temizle';

  @override
  String get filterAuto => 'Otomatik';

  @override
  String get filterOriginal => 'Orijinal';

  @override
  String get filterColor => 'Renkli';

  @override
  String get filterGrayscale => 'Gri tonlama';

  @override
  String get toolbarCrop => 'Kırp';

  @override
  String get toolbarRotate => 'Döndür';

  @override
  String get toolbarFilter => 'Filtre';

  @override
  String get toolbarText => 'Metin';

  @override
  String get cropHandleTopEdge => 'Üst kenar orta noktası';

  @override
  String get cropHandleRightEdge => 'Sağ kenar orta noktası';

  @override
  String get cropHandleBottomEdge => 'Alt kenar orta noktası';

  @override
  String get cropHandleLeftEdge => 'Sol kenar orta noktası';

  @override
  String get cropHandleTopLeft => 'Sol üst kırpma köşesi';

  @override
  String get cropHandleTopRight => 'Sağ üst kırpma köşesi';

  @override
  String get cropHandleBottomRight => 'Sağ alt kırpma köşesi';

  @override
  String get cropHandleBottomLeft => 'Sol alt kırpma köşesi';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Bu belge silinsin mi? Bu işlem geri alınamaz.';

  @override
  String get viewerDeleteDocumentError => 'Silinemedi';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Bu tek sayfa. Silmek tüm belgeyi kaldırır.';

  @override
  String get viewerDeletePageConfirm =>
      'Bu sayfa silinsin mi? Bu işlem geri alınamaz.';

  @override
  String get viewerDeletePageError => 'Sayfa silinemedi';

  @override
  String get viewerExportPdfError => 'PDF dışa aktarılamadı';

  @override
  String get viewerShareImageError => 'Görsel paylaşılamadı';

  @override
  String get viewerShareImagesError => 'Görseller paylaşılamadı';

  @override
  String get viewerPrintSuccess => 'Yazıcıya gönderildi';

  @override
  String get viewerPrintError => 'Yazdırılamadı';

  @override
  String get viewerProtectPdfSuccess => 'Korumalı PDF hazır';

  @override
  String get viewerProtectPdfError => 'PDF korunamadı';

  @override
  String get viewerSplitLastPageWarning =>
      'Bu son sayfa — sonrasında bölünecek bir şey yok.';

  @override
  String get viewerSplitSuccess => 'Yeni bir belgeye bölündü';

  @override
  String get viewerSplitError => 'Bölünemedi';

  @override
  String get viewerMergeError => 'Birleştirilemedi';

  @override
  String get viewerReorderPagesError => 'Sayfalar yeniden sıralanamadı';

  @override
  String get viewerRotateError => 'Döndürülemedi';

  @override
  String get viewerCropError => 'Kırpma güncellenemedi';

  @override
  String get viewerFilterError => 'Filtre değiştirilemedi';

  @override
  String get viewerLoadError => 'Bu belge yüklenemedi.';

  @override
  String get viewerEmptyPages => 'Bu belgede sayfa yok.';

  @override
  String get viewerMenuMerge => 'Başka bir belgeyi birleştir…';

  @override
  String get viewerMenuSplit => 'Bu sayfadan sonra böl';

  @override
  String get viewerMenuDeleteDocument => 'Belgeyi sil';

  @override
  String get viewerShareExportPdf => 'PDF dışa aktar';

  @override
  String get viewerShareAsImage => 'Görsel olarak paylaş';

  @override
  String get viewerShareAllAsImages => 'Tümünü görsel olarak paylaş';

  @override
  String get viewerSharePrint => 'Yazdır';

  @override
  String get viewerShareProtect => 'Şifreyle koru';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Bağlantı paylaş';

  @override
  String get shareFax => 'Faks';

  @override
  String get shareLinkUnavailable => 'Bağlantı paylaşımı henüz kullanılamıyor';

  @override
  String get shareFaxUnavailable => 'Faks henüz kullanılamıyor';

  @override
  String get renameDialogTitle => 'Belgeyi yeniden adlandır';

  @override
  String get renameFieldLabel => 'Ad';

  @override
  String get passwordDialogTitle => 'PDF\'yi şifreyle koru';

  @override
  String get passwordFieldHint => 'Bir şifre girin';

  @override
  String get passwordProtectButton => 'Koru';

  @override
  String get exportQualityTitle => 'Dışa aktarma kalitesi';

  @override
  String get exportQualityOriginal => 'Orijinal';

  @override
  String get exportQualityOriginalDesc => 'Tam kalite, en büyük dosya';

  @override
  String get exportQualityHigh => 'Yüksek';

  @override
  String get exportQualityHighDesc => 'Yüksek kalite';

  @override
  String get exportQualityMedium => 'Orta';

  @override
  String get exportQualityMediumDesc => 'E-posta için uygun';

  @override
  String get exportQualityLow => 'Düşük';

  @override
  String get exportQualityLowDesc => 'En küçük dosya';

  @override
  String get mergeDialogTitle => 'Başka bir belgeyi birleştir';

  @override
  String get mergeDialogEmpty => 'Birleştirilecek başka belge yok.';

  @override
  String get ocrTitle => 'Tanınan metin';

  @override
  String get ocrErrorRecognize => 'Metin tanınamadı';

  @override
  String get ocrErrorExport => 'Metin dışa aktarılamadı';

  @override
  String get ocrTextLayerReady => 'Metin katmanı hazır · aramayı destekler';

  @override
  String get ocrCopyText => 'Metni kopyala';

  @override
  String get ocrShareTxt => '.txt paylaş';

  @override
  String get ocrEmpty => 'Bu sayfada henüz tanınan metin yok.';

  @override
  String get ocrRecognizeButton => 'Metni tanı';

  @override
  String get pdfPreviewOpenError => 'PDF açılamadı.';

  @override
  String get feedbackTitle => 'Geri bildirim gönder';

  @override
  String get feedbackSuccess => 'Teşekkürler! Geri bildiriminiz gönderildi.';

  @override
  String get feedbackRateLimited =>
      'Zaten birkaç tane gönderdiniz — lütfen daha sonra tekrar deneyin.';

  @override
  String get feedbackRejectedUnverified =>
      'Uygulama doğrulanamadı — lütfen tekrar deneyin.';

  @override
  String get feedbackOffline => 'Bağlantınızı kontrol edip tekrar deneyin.';

  @override
  String get feedbackInvalid =>
      'Lütfen mesajınızı kontrol edip tekrar deneyin.';

  @override
  String get feedbackServerError =>
      'Şu anda gönderilemedi — lütfen tekrar deneyin.';

  @override
  String get feedbackTypeLabel => 'Tür';

  @override
  String get feedbackTypeBug => 'Hata';

  @override
  String get feedbackTypeIdea => 'Fikir';

  @override
  String get feedbackTypeQuestion => 'Soru';

  @override
  String get feedbackMessageLabel => 'Mesaj';

  @override
  String get feedbackMessageHint => 'Geri bildiriminiz';

  @override
  String get feedbackMessageRequired => 'Lütfen bir mesaj girin';

  @override
  String get feedbackEmailLabel => 'E-posta — isteğe bağlı';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid =>
      'Geçerli bir e-posta girin veya boş bırakın';

  @override
  String get feedbackEmailPublicNote =>
      'İsteğe bağlı. Bu, GitHub\'da herkese açık olarak görünecektir.';

  @override
  String get feedbackDiagnosticsShow => 'Neler gönderilecek?';

  @override
  String get feedbackDiagnosticsHide => 'Gönderilecekleri gizle';

  @override
  String get feedbackDiagnosticsTitle => 'Neleri dahil ediyoruz';

  @override
  String get feedbackDiagnosticsBody =>
      'Eklenen tanılama bilgileri: uygulama sürümü, işletim sistemi sürümü, cihaz modeli ve dil. Taranan belgeler veya içerikleri asla gönderilmez.';

  @override
  String get feedbackSubmit => 'Raporu gönder';
}
