// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get commonRetake => 'Переснять';

  @override
  String get commonShare => 'Поделиться';

  @override
  String get commonRename => 'Переименовать';

  @override
  String get commonCopied => 'Скопировано';

  @override
  String get commonDocumentOptions => 'Параметры документа';

  @override
  String get commonSearchHint => 'Поиск по названиям и тексту страниц';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count страницы',
      many: '$count страниц',
      few: '$count страницы',
      one: '$count страница',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument =>
      'Не удалось сохранить документ. Попробуйте ещё раз.';

  @override
  String get commonErrorRename => 'Не удалось переименовать';

  @override
  String get commonErrorShare => 'Не удалось поделиться';

  @override
  String get homeDocumentsTitle => 'Документы';

  @override
  String get homePrivateOnDevice => 'Конфиденциально · на этом устройстве';

  @override
  String get homeCancelSelectionTooltip => 'Отменить выбор';

  @override
  String homeSelectedCount(int count) {
    return 'Выбрано: $count';
  }

  @override
  String get homeExportTooltip => 'Экспорт';

  @override
  String get homeActionScan => 'Скан';

  @override
  String get homeActionIdCard => 'ID-карта';

  @override
  String get homeActionImport => 'Импорт';

  @override
  String homeSearchNoMatch(String query) {
    return 'Нет документов, соответствующих «$query».';
  }

  @override
  String get homeErrorLoadDocuments => 'Не удалось загрузить документы.';

  @override
  String get homeErrorImportPhoto => 'Не удалось импортировать фото';

  @override
  String get homeViewList => 'Список';

  @override
  String get homeViewGrid => 'Сетка';

  @override
  String get homeEmptyTitle => 'Пока нет документов';

  @override
  String get homeEmptySubtitle =>
      'Нажмите «Скан», чтобы создать первый документ';

  @override
  String get sortName => 'Имя';

  @override
  String get sortCreated => 'Дата создания';

  @override
  String get sortModified => 'Дата изменения';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsSectionAppearance => 'Внешний вид';

  @override
  String get settingsThemeLight => 'Светлая';

  @override
  String get settingsThemeDark => 'Тёмная';

  @override
  String get settingsThemeSystem => 'Системная';

  @override
  String get settingsSectionLanguage => 'Язык';

  @override
  String get settingsLanguageSystem => 'Как в системе';

  @override
  String get settingsSectionFeedback => 'Отзывы и поддержка';

  @override
  String get settingsSupportApp => 'Поддержать приложение';

  @override
  String get settingsAboutTagline =>
      'Ваши сканы остаются на вашем устройстве — без аккаунта, без облака.';

  @override
  String get donationHeadline => 'Без аккаунтов. Без облака.\\nБез подписки.';

  @override
  String get donationDisclaimer =>
      'Это исключительно добровольное пожертвование. Взамен вы не получаете никаких функций, преимуществ или контента — оно просто помогает поддерживать развитие проекта.';

  @override
  String get donationOptionalNote =>
      'Пожертвование ничего не разблокирует — все функции уже доступны вам. Это действительно необязательно.';

  @override
  String get donationKofiButton => 'Угостить кофе — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Не удалось открыть Ko-fi';

  @override
  String get donationBitcoinCopied => 'Адрес Bitcoin скопирован';

  @override
  String get donationBitcoinHeading => 'Или пожертвуйте в Bitcoin';

  @override
  String get donationCopyAddress => 'Скопировать адрес';

  @override
  String get donationBannerText =>
      'Нравится приложение? Нажмите, чтобы поддержать';

  @override
  String get scanTitle => 'Сканирование';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Сохранено $count страницы',
      many: 'Сохранено $count страниц',
      few: 'Сохранено $count страницы',
      one: 'Сохранена $count страница',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'Не удалось заменить страницу. Попробуйте ещё раз.';

  @override
  String get scanSaveFailed => 'Не удалось сохранить скан.';

  @override
  String get idScanTitle => 'Сканировать ID';

  @override
  String get idScanFrontPrompt => 'Отсканируйте ЛИЦЕВУЮ сторону ID';

  @override
  String get idScanBackPrompt => 'Отсканируйте ОБРАТНУЮ сторону ID';

  @override
  String get idScanSaving => 'Сохранение…';

  @override
  String get idScanErrorSave => 'Не удалось сохранить ID. Попробуйте ещё раз.';

  @override
  String get idScanErrorBackRetake =>
      'Лицевая сторона сохранена, но не удалось сохранить обратную. Пересканируйте её из документа.';

  @override
  String get captureReviewTitle => 'Просмотр';

  @override
  String get captureReviewReset => 'Сбросить';

  @override
  String get captureReviewAccept => 'Принять';

  @override
  String get editFilterTitle => 'Фильтр';

  @override
  String get editCropTitle => 'Проверка и очистка';

  @override
  String get filterAuto => 'Авто';

  @override
  String get filterOriginal => 'Оригинал';

  @override
  String get filterColor => 'Цвет';

  @override
  String get filterGrayscale => 'Ч/б';

  @override
  String get toolbarCrop => 'Обрезка';

  @override
  String get toolbarRotate => 'Поворот';

  @override
  String get toolbarFilter => 'Фильтр';

  @override
  String get toolbarText => 'Текст';

  @override
  String get cropHandleTopEdge => 'Середина верхнего края';

  @override
  String get cropHandleRightEdge => 'Середина правого края';

  @override
  String get cropHandleBottomEdge => 'Середина нижнего края';

  @override
  String get cropHandleLeftEdge => 'Середина левого края';

  @override
  String get cropHandleTopLeft => 'Верхний левый угол обрезки';

  @override
  String get cropHandleTopRight => 'Верхний правый угол обрезки';

  @override
  String get cropHandleBottomRight => 'Нижний правый угол обрезки';

  @override
  String get cropHandleBottomLeft => 'Нижний левый угол обрезки';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Удалить этот документ? Это действие нельзя отменить.';

  @override
  String get viewerDeleteDocumentError => 'Не удалось удалить';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Это единственная страница. Её удаление удалит весь документ.';

  @override
  String get viewerDeletePageConfirm =>
      'Удалить эту страницу? Это действие нельзя отменить.';

  @override
  String get viewerDeletePageError => 'Не удалось удалить страницу';

  @override
  String get viewerExportPdfError => 'Не удалось экспортировать PDF';

  @override
  String get viewerShareImageError => 'Не удалось поделиться изображением';

  @override
  String get viewerShareImagesError => 'Не удалось поделиться изображениями';

  @override
  String get viewerPrintSuccess => 'Отправлено на печать';

  @override
  String get viewerPrintError => 'Не удалось напечатать';

  @override
  String get viewerProtectPdfSuccess => 'Защищённый PDF готов';

  @override
  String get viewerProtectPdfError => 'Не удалось защитить PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'Это последняя страница — разделять после неё нечего.';

  @override
  String get viewerSplitSuccess => 'Разделено на новый документ';

  @override
  String get viewerSplitError => 'Не удалось разделить';

  @override
  String get viewerMergeError => 'Не удалось объединить';

  @override
  String get viewerReorderPagesError => 'Не удалось изменить порядок страниц';

  @override
  String get viewerRotateError => 'Не удалось повернуть';

  @override
  String get viewerCropError => 'Не удалось обновить обрезку';

  @override
  String get viewerFilterError => 'Не удалось изменить фильтр';

  @override
  String get viewerLoadError => 'Не удалось загрузить этот документ.';

  @override
  String get viewerEmptyPages => 'В этом документе нет страниц.';

  @override
  String get viewerMenuMerge => 'Объединить с другим документом…';

  @override
  String get viewerMenuSplit => 'Разделить после этой страницы';

  @override
  String get viewerMenuDeleteDocument => 'Удалить документ';

  @override
  String get viewerShareExportPdf => 'Экспорт в PDF';

  @override
  String get viewerShareAsImage => 'Поделиться как изображением';

  @override
  String get viewerShareAllAsImages => 'Поделиться всеми как изображениями';

  @override
  String get viewerSharePrint => 'Печать';

  @override
  String get viewerShareProtect => 'Защитить паролем';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Ссылка';

  @override
  String get shareFax => 'Факс';

  @override
  String get shareLinkUnavailable => 'Отправка по ссылке пока недоступна';

  @override
  String get shareFaxUnavailable => 'Отправка по факсу пока недоступна';

  @override
  String get renameDialogTitle => 'Переименовать документ';

  @override
  String get renameFieldLabel => 'Название';

  @override
  String get passwordDialogTitle => 'Защита PDF паролем';

  @override
  String get passwordFieldHint => 'Введите пароль';

  @override
  String get passwordProtectButton => 'Защитить';

  @override
  String get exportQualityTitle => 'Качество экспорта';

  @override
  String get exportQualityOriginal => 'Оригинал';

  @override
  String get exportQualityOriginalDesc => 'Полное качество, самый большой файл';

  @override
  String get exportQualityHigh => 'Высокое';

  @override
  String get exportQualityHighDesc => 'Высокое качество';

  @override
  String get exportQualityMedium => 'Среднее';

  @override
  String get exportQualityMediumDesc => 'Подходит для email';

  @override
  String get exportQualityLow => 'Низкое';

  @override
  String get exportQualityLowDesc => 'Самый маленький файл';

  @override
  String get mergeDialogTitle => 'Объединить с другим документом';

  @override
  String get mergeDialogEmpty => 'Нет других документов для объединения.';

  @override
  String get ocrTitle => 'Распознанный текст';

  @override
  String get ocrErrorRecognize => 'Не удалось распознать текст';

  @override
  String get ocrErrorExport => 'Не удалось экспортировать текст';

  @override
  String get ocrTextLayerReady => 'Текстовый слой готов · работает поиск';

  @override
  String get ocrCopyText => 'Скопировать текст';

  @override
  String get ocrShareTxt => 'Поделиться .txt';

  @override
  String get ocrEmpty => 'На этой странице пока не распознан текст.';

  @override
  String get ocrRecognizeButton => 'Распознать текст';

  @override
  String get pdfPreviewOpenError => 'Не удалось открыть PDF.';

  @override
  String get feedbackTitle => 'Отправить отзыв';

  @override
  String get feedbackSuccess => 'Спасибо! Ваш отзыв отправлен.';

  @override
  String get feedbackRateLimited =>
      'Вы уже отправили несколько отзывов — попробуйте позже.';

  @override
  String get feedbackRejectedUnverified =>
      'Не удалось проверить приложение — попробуйте ещё раз.';

  @override
  String get feedbackOffline => 'Проверьте подключение и попробуйте ещё раз.';

  @override
  String get feedbackInvalid => 'Проверьте сообщение и попробуйте ещё раз.';

  @override
  String get feedbackServerError =>
      'Не удалось отправить сейчас — попробуйте ещё раз.';

  @override
  String get feedbackTypeLabel => 'Тип';

  @override
  String get feedbackTypeBug => 'Ошибка';

  @override
  String get feedbackTypeIdea => 'Идея';

  @override
  String get feedbackTypeQuestion => 'Вопрос';

  @override
  String get feedbackMessageLabel => 'Сообщение';

  @override
  String get feedbackMessageHint => 'Ваш отзыв';

  @override
  String get feedbackMessageRequired => 'Введите сообщение';

  @override
  String get feedbackEmailLabel => 'Email — необязательно';

  @override
  String get feedbackEmailHint => 'you@example.com';

  @override
  String get feedbackEmailInvalid =>
      'Введите корректный email или оставьте поле пустым';

  @override
  String get feedbackEmailPublicNote =>
      'Необязательно. Будет видно всем на GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'Что будет отправлено?';

  @override
  String get feedbackDiagnosticsHide => 'Скрыть, что будет отправлено';

  @override
  String get feedbackDiagnosticsTitle => 'Что мы включаем';

  @override
  String get feedbackDiagnosticsBody =>
      'Прилагается диагностика: версия приложения, версия ОС, модель устройства и язык. Отсканированные документы и их содержимое никогда не отправляются.';

  @override
  String get feedbackSubmit => 'Отправить отчёт';
}
