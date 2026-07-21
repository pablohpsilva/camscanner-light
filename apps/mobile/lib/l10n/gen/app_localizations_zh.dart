// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => '取消';

  @override
  String get commonSave => '保存';

  @override
  String get commonDelete => '删除';

  @override
  String get commonRetry => '重试';

  @override
  String get commonRetake => '重拍';

  @override
  String get commonShare => '分享';

  @override
  String get commonRename => '重命名';

  @override
  String get commonCopied => '已复制';

  @override
  String get commonDocumentOptions => '文档选项';

  @override
  String get commonSearchHint => '搜索标题和页面内文字';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count 页',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument => '无法保存文档，请重试。';

  @override
  String get commonErrorRename => '无法重命名';

  @override
  String get commonErrorShare => '无法分享';

  @override
  String get homeDocumentsTitle => '文档';

  @override
  String get homePrivateOnDevice => '私密 · 仅保存在本设备';

  @override
  String get homeCancelSelectionTooltip => '取消选择';

  @override
  String homeSelectedCount(int count) {
    return '已选择 $count 项';
  }

  @override
  String get homeExportTooltip => '导出';

  @override
  String get homeActionScan => '扫描';

  @override
  String get homeActionIdCard => '证件';

  @override
  String get homeActionImport => '导入';

  @override
  String homeSearchNoMatch(String query) {
    return '没有与“$query”匹配的文档。';
  }

  @override
  String get homeErrorLoadDocuments => '无法加载文档。';

  @override
  String get homeErrorImportPhoto => '无法导入照片';

  @override
  String get homeViewList => '列表';

  @override
  String get homeViewGrid => '网格';

  @override
  String get homeEmptyTitle => '暂无文档';

  @override
  String get homeEmptySubtitle => '点击“扫描”创建第一份文档';

  @override
  String get sortName => '名称';

  @override
  String get sortCreated => '创建时间';

  @override
  String get sortModified => '修改时间';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsSectionAppearance => '外观';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeSystem => '跟随系统';

  @override
  String get settingsSectionLanguage => '语言';

  @override
  String get settingsLanguageSystem => '系统默认';

  @override
  String get settingsSectionFeedback => '反馈与支持';

  @override
  String get settingsSupportApp => '支持本应用';

  @override
  String get settingsAboutTagline => '扫描内容仅保存在本设备——无需账号，不上传云端。';

  @override
  String get donationHeadline => '无需账号。不上传云端。\n无需订阅。';

  @override
  String get donationDisclaimer => '这只是自愿捐赠，您不会因此获得任何功能、权益或内容——它只是帮助支持项目的持续开发。';

  @override
  String get donationOptionalNote => '捐赠不会解锁任何内容，所有功能本就免费提供。这完全是自愿的。';

  @override
  String get donationKofiButton => '请我喝杯咖啡 — Ko-fi';

  @override
  String get donationErrorOpenKofi => '无法打开 Ko-fi';

  @override
  String get donationBitcoinCopied => '比特币地址已复制';

  @override
  String get donationBitcoinHeading => '或使用比特币捐赠';

  @override
  String get donationCopyAddress => '复制地址';

  @override
  String get donationBannerText => '喜欢这款应用？点击支持一下';

  @override
  String donationTipButtonLabel(String price) {
    return '打赏 $price';
  }

  @override
  String get donationTipThankYouTitle => '谢谢 ❤️';

  @override
  String get donationTipThankYouBody => '你的支持让这个应用持续运行。';

  @override
  String get donationTipThankYouClose => '关闭';

  @override
  String get donationTipUnavailable => '打赏暂时不可用，请稍后再试。';

  @override
  String get donationTipError => '无法完成打赏';

  @override
  String get scanTitle => '扫描';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '已保存 $count 页',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage => '无法替换页面，请重试。';

  @override
  String get scanSaveFailed => '无法保存扫描内容。';

  @override
  String get idScanTitle => '扫描证件';

  @override
  String get idScanFrontPrompt => '请扫描证件正面';

  @override
  String get idScanBackPrompt => '请扫描证件背面';

  @override
  String get idScanSaving => '保存中…';

  @override
  String get idScanErrorSave => '无法保存证件，请重试。';

  @override
  String get idScanErrorBackRetake => '正面已保存，但背面保存失败，请从文档中重新拍摄。';

  @override
  String get captureReviewTitle => '预览';

  @override
  String get captureReviewReset => '重置';

  @override
  String get captureReviewAccept => '确认';

  @override
  String get editFilterTitle => '滤镜';

  @override
  String get editCropTitle => '查看并清理';

  @override
  String get filterAuto => '自动';

  @override
  String get filterOriginal => '原图';

  @override
  String get filterColor => '彩色';

  @override
  String get filterGrayscale => '灰度';

  @override
  String get toolbarCrop => '裁剪';

  @override
  String get toolbarRotate => '旋转';

  @override
  String get toolbarFilter => '滤镜';

  @override
  String get toolbarText => '文字';

  @override
  String get cropHandleTopEdge => '上边中点';

  @override
  String get cropHandleRightEdge => '右边中点';

  @override
  String get cropHandleBottomEdge => '下边中点';

  @override
  String get cropHandleLeftEdge => '左边中点';

  @override
  String get cropHandleTopLeft => '左上角裁剪点';

  @override
  String get cropHandleTopRight => '右上角裁剪点';

  @override
  String get cropHandleBottomRight => '右下角裁剪点';

  @override
  String get cropHandleBottomLeft => '左下角裁剪点';

  @override
  String get viewerDeleteDocumentConfirm => '删除此文档？此操作无法撤销。';

  @override
  String get viewerDeleteDocumentError => '无法删除';

  @override
  String get viewerDeletePageOnlyPageWarning => '这是唯一的一页，删除后整个文档都会被删除。';

  @override
  String get viewerDeletePageConfirm => '删除此页？此操作无法撤销。';

  @override
  String get viewerDeletePageError => '无法删除该页';

  @override
  String get viewerExportPdfError => '无法导出 PDF';

  @override
  String get viewerShareImageError => '无法分享图片';

  @override
  String get viewerShareImagesError => '无法分享图片';

  @override
  String get viewerPrintSuccess => '已发送至打印机';

  @override
  String get viewerPrintError => '无法打印';

  @override
  String get viewerProtectPdfSuccess => '受保护的 PDF 已生成';

  @override
  String get viewerProtectPdfError => '无法保护 PDF';

  @override
  String get viewerSplitLastPageWarning => '这是最后一页——之后没有内容可拆分。';

  @override
  String get viewerSplitSuccess => '已拆分为新文档';

  @override
  String get viewerSplitError => '无法拆分';

  @override
  String get viewerMergeError => '无法合并';

  @override
  String get viewerReorderPagesError => '无法调整页面顺序';

  @override
  String get viewerRotateError => '无法旋转';

  @override
  String get viewerCropError => '无法更新裁剪';

  @override
  String get viewerFilterError => '无法更改滤镜';

  @override
  String get viewerLoadError => '无法加载此文档。';

  @override
  String get viewerEmptyPages => '此文档没有页面。';

  @override
  String get viewerMenuMerge => '合并其他文档…';

  @override
  String get viewerMenuSplit => '从此页之后拆分';

  @override
  String get viewerMenuDeleteDocument => '删除文档';

  @override
  String get viewerShareExportPdf => '导出 PDF';

  @override
  String get viewerShareAsImage => '以图片形式分享';

  @override
  String get viewerShareAllAsImages => '以图片形式分享全部';

  @override
  String get viewerSharePrint => '打印';

  @override
  String get viewerShareProtect => '设置密码保护';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => '分享链接';

  @override
  String get shareFax => '传真';

  @override
  String get shareLinkUnavailable => '链接分享功能暂未开放';

  @override
  String get shareFaxUnavailable => '传真功能暂未开放';

  @override
  String get renameDialogTitle => '重命名文档';

  @override
  String get renameFieldLabel => '名称';

  @override
  String get passwordDialogTitle => '为 PDF 设置密码保护';

  @override
  String get passwordFieldHint => '输入密码';

  @override
  String get passwordProtectButton => '保护';

  @override
  String get exportQualityTitle => '导出质量';

  @override
  String get exportQualityOriginal => '原始质量';

  @override
  String get exportQualityOriginalDesc => '质量最高，文件最大';

  @override
  String get exportQualityHigh => '高';

  @override
  String get exportQualityHighDesc => '高质量';

  @override
  String get exportQualityMedium => '中';

  @override
  String get exportQualityMediumDesc => '适合邮件发送';

  @override
  String get exportQualityLow => '低';

  @override
  String get exportQualityLowDesc => '文件最小';

  @override
  String get mergeDialogTitle => '合并其他文档';

  @override
  String get mergeDialogEmpty => '没有其他可合并的文档。';

  @override
  String get ocrTitle => '识别的文字';

  @override
  String get ocrErrorRecognize => '无法识别文字';

  @override
  String get ocrErrorExport => '无法导出文字';

  @override
  String get ocrTextLayerReady => '文字层已就绪 · 支持搜索';

  @override
  String get ocrCopyText => '复制文字';

  @override
  String get ocrShareTxt => '分享 .txt';

  @override
  String get ocrEmpty => '此页尚未识别出文字。';

  @override
  String get ocrRecognizeButton => '识别文字';

  @override
  String get pdfPreviewOpenError => '无法打开该 PDF。';

  @override
  String get feedbackTitle => '发送反馈';

  @override
  String get feedbackSuccess => '谢谢！反馈已发送。';

  @override
  String get feedbackRateLimited => '您已发送过几条反馈，请稍后再试。';

  @override
  String get feedbackRejectedUnverified => '无法验证应用，请重试。';

  @override
  String get feedbackOffline => '请检查网络连接后重试。';

  @override
  String get feedbackInvalid => '请检查您的留言内容后重试。';

  @override
  String get feedbackServerError => '暂时无法发送，请稍后重试。';

  @override
  String get feedbackTypeLabel => '类型';

  @override
  String get feedbackTypeBug => '问题反馈';

  @override
  String get feedbackTypeIdea => '建议';

  @override
  String get feedbackTypeQuestion => '咨询';

  @override
  String get feedbackMessageLabel => '留言';

  @override
  String get feedbackMessageHint => '请输入您的反馈';

  @override
  String get feedbackMessageRequired => '请输入留言内容';

  @override
  String get feedbackEmailLabel => '邮箱（选填）';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid => '请输入有效邮箱，或留空';

  @override
  String get feedbackEmailPublicNote => '选填。此邮箱将在 GitHub 上公开显示。';

  @override
  String get feedbackDiagnosticsShow => '将发送哪些内容？';

  @override
  String get feedbackDiagnosticsHide => '隐藏发送内容';

  @override
  String get feedbackDiagnosticsTitle => '我们会包含以下内容';

  @override
  String get feedbackDiagnosticsBody =>
      '附带的诊断信息包括：应用版本、系统版本、设备型号和语言。绝不会发送任何扫描文档或其内容。';

  @override
  String get feedbackSubmit => '发送反馈';
}
