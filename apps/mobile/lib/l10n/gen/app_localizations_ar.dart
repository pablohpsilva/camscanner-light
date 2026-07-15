// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'إلغاء';

  @override
  String get commonSave => 'حفظ';

  @override
  String get commonDelete => 'حذف';

  @override
  String get commonRetry => 'إعادة المحاولة';

  @override
  String get commonRetake => 'إعادة الالتقاط';

  @override
  String get commonShare => 'مشاركة';

  @override
  String get commonRename => 'إعادة تسمية';

  @override
  String get commonCopied => 'تم النسخ';

  @override
  String get commonDocumentOptions => 'خيارات المستند';

  @override
  String get commonSearchHint => 'ابحث في العناوين والنص داخل الصفحات';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count صفحة',
      many: '$count صفحة',
      few: '$count صفحات',
      two: 'صفحتان',
      one: 'صفحة واحدة',
      zero: '$count صفحة',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument => 'تعذّر حفظ المستند. حاول مرة أخرى.';

  @override
  String get commonErrorRename => 'تعذّرت إعادة التسمية';

  @override
  String get commonErrorShare => 'تعذّرت المشاركة';

  @override
  String get homeDocumentsTitle => 'المستندات';

  @override
  String get homePrivateOnDevice => 'خاص · على هذا الجهاز';

  @override
  String get homeCancelSelectionTooltip => 'إلغاء التحديد';

  @override
  String homeSelectedCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم تحديد $count عنصر',
      many: 'تم تحديد $count عنصرًا',
      few: 'تم تحديد $count عناصر',
      two: 'تم تحديد عنصرين',
      one: 'تم تحديد عنصر واحد',
      zero: 'تم تحديد $count',
    );
    return '$_temp0';
  }

  @override
  String get homeExportTooltip => 'تصدير';

  @override
  String get homeActionScan => 'مسح ضوئي';

  @override
  String get homeActionIdCard => 'بطاقة هوية';

  @override
  String get homeActionImport => 'استيراد';

  @override
  String homeSearchNoMatch(String query) {
    return 'لا توجد مستندات مطابقة لـ \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments => 'تعذّر تحميل المستندات.';

  @override
  String get homeErrorImportPhoto => 'تعذّر استيراد الصورة';

  @override
  String get homeViewList => 'قائمة';

  @override
  String get homeViewGrid => 'شبكة';

  @override
  String get homeEmptyTitle => 'لا توجد مستندات بعد';

  @override
  String get homeEmptySubtitle => 'اضغط على مسح ضوئي لإنشاء أول مستند لك';

  @override
  String get sortName => 'الاسم';

  @override
  String get sortCreated => 'تاريخ الإنشاء';

  @override
  String get sortModified => 'تاريخ التعديل';

  @override
  String get settingsTitle => 'الإعدادات';

  @override
  String get settingsSectionAppearance => 'المظهر';

  @override
  String get settingsThemeLight => 'فاتح';

  @override
  String get settingsThemeDark => 'داكن';

  @override
  String get settingsThemeSystem => 'النظام';

  @override
  String get settingsSectionLanguage => 'اللغة';

  @override
  String get settingsLanguageSystem => 'لغة النظام';

  @override
  String get settingsSectionFeedback => 'الملاحظات والدعم';

  @override
  String get settingsSupportApp => 'ادعم التطبيق';

  @override
  String get settingsAboutTagline =>
      'تبقى مسحوباتك الضوئية على جهازك — بلا حساب وبلا سحابة.';

  @override
  String get donationHeadline => 'بلا حسابات. بلا سحابة.\\nبلا اشتراك.';

  @override
  String get donationDisclaimer =>
      'هذا تبرّع اختياري فقط. لن تحصل على أي ميزات أو مزايا أو محتوى مقابله — فهو يساعد ببساطة على دعم تطوير التطبيق.';

  @override
  String get donationOptionalNote =>
      'التبرّع لا يفتح أي شيء — فكل الميزات متاحة لك بالفعل. هذا أمر اختياري تمامًا.';

  @override
  String get donationKofiButton => 'اشترِ لي قهوة — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'تعذّر فتح Ko-fi';

  @override
  String get donationBitcoinCopied => 'تم نسخ عنوان Bitcoin';

  @override
  String get donationBitcoinHeading => 'أو تبرّع عبر Bitcoin';

  @override
  String get donationCopyAddress => 'نسخ العنوان';

  @override
  String get donationBannerText => 'هل يعجبك التطبيق؟ اضغط لدعمه';

  @override
  String get scanTitle => 'مسح ضوئي';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'تم حفظ $count صفحة',
      many: 'تم حفظ $count صفحة',
      few: 'تم حفظ $count صفحات',
      two: 'تم حفظ صفحتين',
      one: 'تم حفظ صفحة واحدة',
      zero: 'تم حفظ $count صفحة',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage => 'تعذّر استبدال الصفحة. حاول مرة أخرى.';

  @override
  String get scanSaveFailed => 'تعذّر حفظ المسح الضوئي.';

  @override
  String get idScanTitle => 'مسح بطاقة الهوية';

  @override
  String get idScanFrontPrompt => 'امسح الوجه الأمامي للبطاقة';

  @override
  String get idScanBackPrompt => 'امسح الوجه الخلفي للبطاقة';

  @override
  String get idScanSaving => 'جارٍ الحفظ…';

  @override
  String get idScanErrorSave => 'تعذّر حفظ بطاقة الهوية. حاول مرة أخرى.';

  @override
  String get idScanErrorBackRetake =>
      'تم حفظ الوجه الأمامي، لكن الوجه الخلفي فشل. أعد التقاطه من المستند.';

  @override
  String get captureReviewTitle => 'مراجعة';

  @override
  String get captureReviewReset => 'إعادة ضبط';

  @override
  String get captureReviewAccept => 'قبول';

  @override
  String get editFilterTitle => 'الفلتر';

  @override
  String get editCropTitle => 'مراجعة وتنظيف';

  @override
  String get filterAuto => 'تلقائي';

  @override
  String get filterOriginal => 'أصلي';

  @override
  String get filterColor => 'ملوّن';

  @override
  String get filterGrayscale => 'تدرج رمادي';

  @override
  String get toolbarCrop => 'قص';

  @override
  String get toolbarRotate => 'تدوير';

  @override
  String get toolbarFilter => 'فلتر';

  @override
  String get toolbarText => 'نص';

  @override
  String get cropHandleTopEdge => 'منتصف الحافة العلوية';

  @override
  String get cropHandleRightEdge => 'منتصف الحافة اليمنى';

  @override
  String get cropHandleBottomEdge => 'منتصف الحافة السفلية';

  @override
  String get cropHandleLeftEdge => 'منتصف الحافة اليسرى';

  @override
  String get cropHandleTopLeft => 'زاوية القص العلوية اليسرى';

  @override
  String get cropHandleTopRight => 'زاوية القص العلوية اليمنى';

  @override
  String get cropHandleBottomRight => 'زاوية القص السفلية اليمنى';

  @override
  String get cropHandleBottomLeft => 'زاوية القص السفلية اليسرى';

  @override
  String get viewerDeleteDocumentConfirm =>
      'حذف هذا المستند؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get viewerDeleteDocumentError => 'تعذّر الحذف';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'هذه هي الصفحة الوحيدة. حذفها يؤدي إلى حذف المستند بالكامل.';

  @override
  String get viewerDeletePageConfirm =>
      'حذف هذه الصفحة؟ لا يمكن التراجع عن هذا الإجراء.';

  @override
  String get viewerDeletePageError => 'تعذّر حذف الصفحة';

  @override
  String get viewerExportPdfError => 'تعذّر تصدير ملف PDF';

  @override
  String get viewerShareImageError => 'تعذّرت مشاركة الصورة';

  @override
  String get viewerShareImagesError => 'تعذّرت مشاركة الصور';

  @override
  String get viewerPrintSuccess => 'تم الإرسال إلى الطابعة';

  @override
  String get viewerPrintError => 'تعذّرت الطباعة';

  @override
  String get viewerProtectPdfSuccess => 'ملف PDF المحمي جاهز';

  @override
  String get viewerProtectPdfError => 'تعذّرت حماية ملف PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'هذه هي الصفحة الأخيرة — لا يوجد ما يُقسَّم بعدها.';

  @override
  String get viewerSplitSuccess => 'تم التقسيم إلى مستند جديد';

  @override
  String get viewerSplitError => 'تعذّر التقسيم';

  @override
  String get viewerMergeError => 'تعذّر الدمج';

  @override
  String get viewerReorderPagesError => 'تعذّرت إعادة ترتيب الصفحات';

  @override
  String get viewerRotateError => 'تعذّر التدوير';

  @override
  String get viewerCropError => 'تعذّر تحديث القص';

  @override
  String get viewerFilterError => 'تعذّر تغيير الفلتر';

  @override
  String get viewerLoadError => 'تعذّر تحميل هذا المستند.';

  @override
  String get viewerEmptyPages => 'هذا المستند لا يحتوي على صفحات.';

  @override
  String get viewerMenuMerge => 'دمج مستند آخر…';

  @override
  String get viewerMenuSplit => 'تقسيم بعد هذه الصفحة';

  @override
  String get viewerMenuDeleteDocument => 'حذف المستند';

  @override
  String get viewerShareExportPdf => 'تصدير PDF';

  @override
  String get viewerShareAsImage => 'مشاركة كصورة';

  @override
  String get viewerShareAllAsImages => 'مشاركة الكل كصور';

  @override
  String get viewerSharePrint => 'طباعة';

  @override
  String get viewerShareProtect => 'حماية بكلمة مرور';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'مشاركة رابط';

  @override
  String get shareFax => 'فاكس';

  @override
  String get shareLinkUnavailable => 'مشاركة الروابط غير متاحة بعد';

  @override
  String get shareFaxUnavailable => 'الفاكس غير متاح بعد';

  @override
  String get renameDialogTitle => 'إعادة تسمية المستند';

  @override
  String get renameFieldLabel => 'الاسم';

  @override
  String get passwordDialogTitle => 'حماية ملف PDF بكلمة مرور';

  @override
  String get passwordFieldHint => 'أدخل كلمة مرور';

  @override
  String get passwordProtectButton => 'حماية';

  @override
  String get exportQualityTitle => 'جودة التصدير';

  @override
  String get exportQualityOriginal => 'أصلية';

  @override
  String get exportQualityOriginalDesc => 'جودة كاملة، أكبر حجم ملف';

  @override
  String get exportQualityHigh => 'عالية';

  @override
  String get exportQualityHighDesc => 'جودة عالية';

  @override
  String get exportQualityMedium => 'متوسطة';

  @override
  String get exportQualityMediumDesc => 'مناسبة للبريد الإلكتروني';

  @override
  String get exportQualityLow => 'منخفضة';

  @override
  String get exportQualityLowDesc => 'أصغر حجم ملف';

  @override
  String get mergeDialogTitle => 'دمج مستند آخر';

  @override
  String get mergeDialogEmpty => 'لا توجد مستندات أخرى للدمج.';

  @override
  String get ocrTitle => 'النص المتعرَّف عليه';

  @override
  String get ocrErrorRecognize => 'تعذّر التعرّف على النص';

  @override
  String get ocrErrorExport => 'تعذّر تصدير النص';

  @override
  String get ocrTextLayerReady => 'طبقة النص جاهزة · تُفعّل البحث';

  @override
  String get ocrCopyText => 'نسخ النص';

  @override
  String get ocrShareTxt => 'مشاركة ملف .txt';

  @override
  String get ocrEmpty => 'لم يتم التعرّف على أي نص في هذه الصفحة بعد.';

  @override
  String get ocrRecognizeButton => 'التعرّف على النص';

  @override
  String get pdfPreviewOpenError => 'تعذّر فتح ملف PDF.';

  @override
  String get feedbackTitle => 'إرسال ملاحظات';

  @override
  String get feedbackSuccess => 'شكرًا لك! تم إرسال ملاحظاتك.';

  @override
  String get feedbackRateLimited =>
      'لقد أرسلت عدة رسائل بالفعل — يُرجى المحاولة لاحقًا.';

  @override
  String get feedbackRejectedUnverified =>
      'تعذّر التحقق من التطبيق — يُرجى المحاولة مرة أخرى.';

  @override
  String get feedbackOffline => 'تحقق من اتصالك وحاول مرة أخرى.';

  @override
  String get feedbackInvalid => 'يُرجى التحقق من رسالتك والمحاولة مرة أخرى.';

  @override
  String get feedbackServerError =>
      'تعذّر الإرسال الآن — يُرجى المحاولة مرة أخرى.';

  @override
  String get feedbackTypeLabel => 'النوع';

  @override
  String get feedbackTypeBug => 'خلل';

  @override
  String get feedbackTypeIdea => 'فكرة';

  @override
  String get feedbackTypeQuestion => 'سؤال';

  @override
  String get feedbackMessageLabel => 'الرسالة';

  @override
  String get feedbackMessageHint => 'ملاحظاتك';

  @override
  String get feedbackMessageRequired => 'يُرجى إدخال رسالة';

  @override
  String get feedbackEmailLabel => 'البريد الإلكتروني — اختياري';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid =>
      'أدخل بريدًا إلكترونيًا صالحًا أو اتركه فارغًا';

  @override
  String get feedbackEmailPublicNote =>
      'اختياري. سيكون هذا مرئيًا للعامة على GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'ماذا سيتم إرساله؟';

  @override
  String get feedbackDiagnosticsHide => 'إخفاء ما سيتم إرساله';

  @override
  String get feedbackDiagnosticsTitle => 'ما نقوم بتضمينه';

  @override
  String get feedbackDiagnosticsBody =>
      'التشخيصات المرفقة: إصدار التطبيق، إصدار نظام التشغيل، طراز الجهاز، واللغة. لا يتم إرسال أي مستندات ممسوحة ضوئيًا أو محتواها مطلقًا.';

  @override
  String get feedbackSubmit => 'إرسال التقرير';
}
