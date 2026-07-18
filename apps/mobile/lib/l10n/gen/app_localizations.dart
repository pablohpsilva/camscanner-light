import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_lb.dart';
import 'app_localizations_pt.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'gen/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ar'),
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('lb'),
    Locale('pt'),
    Locale('pt', 'BR'),
    Locale('ru'),
    Locale('tr'),
    Locale('zh'),
  ];

  /// Brand name — MaterialApp title, Settings About; same in all languages
  ///
  /// In en, this message translates to:
  /// **'CamScanner-light'**
  String get appTitle;

  /// Dialogs
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Dialogs, edit screens
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// Dialogs, toolbar
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// Error screens
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Toolbar, capture review
  ///
  /// In en, this message translates to:
  /// **'Retake'**
  String get commonRetake;

  /// Toolbar, menus, tooltip
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get commonShare;

  /// Menus
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get commonRename;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get commonCopied;

  /// List-item menu tooltip
  ///
  /// In en, this message translates to:
  /// **'Document options'**
  String get commonDocumentOptions;

  /// Search field
  ///
  /// In en, this message translates to:
  /// **'Search titles & text inside pages'**
  String get commonSearchHint;

  /// Page count under a document (list + merge dialog)
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page} other{{count} pages}}'**
  String commonPageCount(int count);

  /// Home, scan
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save document. Try again.'**
  String get commonErrorSaveDocument;

  /// Home, viewer
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rename'**
  String get commonErrorRename;

  /// Home
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share'**
  String get commonErrorShare;

  /// Home header title
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get homeDocumentsTitle;

  /// Home subheader
  ///
  /// In en, this message translates to:
  /// **'Private · on this device'**
  String get homePrivateOnDevice;

  /// Selection bar tooltip
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get homeCancelSelectionTooltip;

  /// Selection bar counter
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String homeSelectedCount(int count);

  /// Selection bar tooltip
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get homeExportTooltip;

  /// Home action button
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get homeActionScan;

  /// Home action button
  ///
  /// In en, this message translates to:
  /// **'ID card'**
  String get homeActionIdCard;

  /// Home action button
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get homeActionImport;

  /// Search empty state
  ///
  /// In en, this message translates to:
  /// **'No documents match \"{query}\".'**
  String homeSearchNoMatch(String query);

  /// Startup error
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load documents.'**
  String get homeErrorLoadDocuments;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t import photo'**
  String get homeErrorImportPhoto;

  /// View-mode toggle
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get homeViewList;

  /// View-mode toggle
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get homeViewGrid;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'No documents yet'**
  String get homeEmptyTitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'Tap Scan to create your first document'**
  String get homeEmptySubtitle;

  /// Sort menu; sort criterion
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get sortName;

  /// Sort menu
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get sortCreated;

  /// Sort menu
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get sortModified;

  /// Settings header
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// Section label
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsSectionAppearance;

  /// Theme segment
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme segment
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Theme segment
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// Section label + picker dialog title
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsSectionLanguage;

  /// Picker option
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settingsLanguageSystem;

  /// Section label
  ///
  /// In en, this message translates to:
  /// **'Feedback & support'**
  String get settingsSectionFeedback;

  /// Settings row + donation title
  ///
  /// In en, this message translates to:
  /// **'Support the app'**
  String get settingsSupportApp;

  /// About footer
  ///
  /// In en, this message translates to:
  /// **'Your scans stay on your device — no account, no cloud.'**
  String get settingsAboutTagline;

  /// Donation hero; keep \n
  ///
  /// In en, this message translates to:
  /// **'No accounts. No cloud.\\nNo subscription.'**
  String get donationHeadline;

  /// Donation body
  ///
  /// In en, this message translates to:
  /// **'This is a voluntary donation only. You receive no features, benefits, or content in return — it simply helps support ongoing development.'**
  String get donationDisclaimer;

  /// Amber note
  ///
  /// In en, this message translates to:
  /// **'Donating unlocks nothing — every feature is already yours. This is genuinely optional.'**
  String get donationOptionalNote;

  /// Button; keep Ko-fi
  ///
  /// In en, this message translates to:
  /// **'Buy me a coffee — Ko-fi'**
  String get donationKofiButton;

  /// Snackbar; keep Ko-fi
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open Ko-fi'**
  String get donationErrorOpenKofi;

  /// Snackbar; keep Bitcoin
  ///
  /// In en, this message translates to:
  /// **'Bitcoin address copied'**
  String get donationBitcoinCopied;

  /// Section heading; keep Bitcoin
  ///
  /// In en, this message translates to:
  /// **'Or donate with Bitcoin'**
  String get donationBitcoinHeading;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Copy address'**
  String get donationCopyAddress;

  /// Home banner
  ///
  /// In en, this message translates to:
  /// **'Enjoying the app? Tap to support it'**
  String get donationBannerText;

  /// Tip jar button; {price} is the StoreKit-localized price
  ///
  /// In en, this message translates to:
  /// **'Tip {price}'**
  String donationTipButtonLabel(String price);

  /// Tip success dialog title
  ///
  /// In en, this message translates to:
  /// **'Thank you ❤️'**
  String get donationTipThankYouTitle;

  /// Tip success dialog body
  ///
  /// In en, this message translates to:
  /// **'Your support keeps this app going.'**
  String get donationTipThankYouBody;

  /// Dismiss the tip thank-you dialog
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get donationTipThankYouClose;

  /// Shown when the store or products fail to load
  ///
  /// In en, this message translates to:
  /// **'Tips aren\'t available right now. Please try again later.'**
  String get donationTipUnavailable;

  /// Snackbar when a tip purchase fails
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t complete your tip'**
  String get donationTipError;

  /// Scan app bar
  ///
  /// In en, this message translates to:
  /// **'Scan'**
  String get scanTitle;

  /// Scan app-bar title after saving
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 page saved} other{{count} pages saved}}'**
  String scanPagesSaved(int count);

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t replace page. Try again.'**
  String get scanErrorReplacePage;

  /// Error body
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the scan.'**
  String get scanSaveFailed;

  /// App bar
  ///
  /// In en, this message translates to:
  /// **'Scan ID'**
  String get idScanTitle;

  /// Status label; keep emphasis
  ///
  /// In en, this message translates to:
  /// **'Scan the FRONT of the ID'**
  String get idScanFrontPrompt;

  /// Status label; keep emphasis
  ///
  /// In en, this message translates to:
  /// **'Scan the BACK of the ID'**
  String get idScanBackPrompt;

  /// Status label
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get idScanSaving;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t save the ID. Try again.'**
  String get idScanErrorSave;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Saved the front, but the back failed. Retake it from the document.'**
  String get idScanErrorBackRetake;

  /// App bar
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get captureReviewTitle;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get captureReviewReset;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Accept'**
  String get captureReviewAccept;

  /// Editor top bar; screen title
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get editFilterTitle;

  /// Crop header
  ///
  /// In en, this message translates to:
  /// **'Review & clean'**
  String get editCropTitle;

  /// Filter strip; filter name
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get filterAuto;

  /// Filter strip
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get filterOriginal;

  /// Filter strip
  ///
  /// In en, this message translates to:
  /// **'Color'**
  String get filterColor;

  /// Filter strip
  ///
  /// In en, this message translates to:
  /// **'Grayscale'**
  String get filterGrayscale;

  /// Editor toolbar; verb
  ///
  /// In en, this message translates to:
  /// **'Crop'**
  String get toolbarCrop;

  /// Editor toolbar; verb
  ///
  /// In en, this message translates to:
  /// **'Rotate'**
  String get toolbarRotate;

  /// Editor toolbar; noun/verb
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get toolbarFilter;

  /// Editor toolbar; OCR entry
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get toolbarText;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Top edge midpoint'**
  String get cropHandleTopEdge;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Right edge midpoint'**
  String get cropHandleRightEdge;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Bottom edge midpoint'**
  String get cropHandleBottomEdge;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Left edge midpoint'**
  String get cropHandleLeftEdge;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Top-left crop corner'**
  String get cropHandleTopLeft;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Top-right crop corner'**
  String get cropHandleTopRight;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Bottom-right crop corner'**
  String get cropHandleBottomRight;

  /// A11y label
  ///
  /// In en, this message translates to:
  /// **'Bottom-left crop corner'**
  String get cropHandleBottomLeft;

  /// Dialog
  ///
  /// In en, this message translates to:
  /// **'Delete this document? This can\'t be undone.'**
  String get viewerDeleteDocumentConfirm;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete'**
  String get viewerDeleteDocumentError;

  /// Dialog
  ///
  /// In en, this message translates to:
  /// **'This is the only page. Deleting it removes the whole document.'**
  String get viewerDeletePageOnlyPageWarning;

  /// Dialog
  ///
  /// In en, this message translates to:
  /// **'Delete this page? This can\'t be undone.'**
  String get viewerDeletePageConfirm;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t delete page'**
  String get viewerDeletePageError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export PDF'**
  String get viewerExportPdfError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share image'**
  String get viewerShareImageError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t share images'**
  String get viewerShareImagesError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Sent to printer'**
  String get viewerPrintSuccess;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t print'**
  String get viewerPrintError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Protected PDF ready'**
  String get viewerProtectPdfSuccess;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t protect PDF'**
  String get viewerProtectPdfError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'This is the last page — nothing to split after.'**
  String get viewerSplitLastPageWarning;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Split into a new document'**
  String get viewerSplitSuccess;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t split'**
  String get viewerSplitError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t merge'**
  String get viewerMergeError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t reorder pages'**
  String get viewerReorderPagesError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t rotate'**
  String get viewerRotateError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t update crop'**
  String get viewerCropError;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t change filter'**
  String get viewerFilterError;

  /// Error body
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t load this document.'**
  String get viewerLoadError;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'This document has no pages.'**
  String get viewerEmptyPages;

  /// Menu item; keep …
  ///
  /// In en, this message translates to:
  /// **'Merge another document…'**
  String get viewerMenuMerge;

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Split after this page'**
  String get viewerMenuSplit;

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Delete document'**
  String get viewerMenuDeleteDocument;

  /// Share sheet
  ///
  /// In en, this message translates to:
  /// **'Export PDF'**
  String get viewerShareExportPdf;

  /// Share sheet
  ///
  /// In en, this message translates to:
  /// **'Share as image'**
  String get viewerShareAsImage;

  /// Share sheet
  ///
  /// In en, this message translates to:
  /// **'Share all as images'**
  String get viewerShareAllAsImages;

  /// Share sheet
  ///
  /// In en, this message translates to:
  /// **'Print'**
  String get viewerSharePrint;

  /// Share sheet
  ///
  /// In en, this message translates to:
  /// **'Protect with password'**
  String get viewerShareProtect;

  /// Page position pill, e.g. 2 / 5
  ///
  /// In en, this message translates to:
  /// **'{current} / {total}'**
  String viewerPageCounter(int current, int total);

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Share link'**
  String get shareLink;

  /// Menu item
  ///
  /// In en, this message translates to:
  /// **'Fax'**
  String get shareFax;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Link sharing isn\'t available yet'**
  String get shareLinkUnavailable;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Fax isn\'t available yet'**
  String get shareFaxUnavailable;

  /// Dialog title
  ///
  /// In en, this message translates to:
  /// **'Rename document'**
  String get renameDialogTitle;

  /// Text field label; noun: document name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get renameFieldLabel;

  /// Dialog title
  ///
  /// In en, this message translates to:
  /// **'Password-protect PDF'**
  String get passwordDialogTitle;

  /// Text field hint
  ///
  /// In en, this message translates to:
  /// **'Enter a password'**
  String get passwordFieldHint;

  /// Dialog action
  ///
  /// In en, this message translates to:
  /// **'Protect'**
  String get passwordProtectButton;

  /// Dialog title
  ///
  /// In en, this message translates to:
  /// **'Export quality'**
  String get exportQualityTitle;

  /// Option label
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get exportQualityOriginal;

  /// Option description
  ///
  /// In en, this message translates to:
  /// **'Full quality, largest file'**
  String get exportQualityOriginalDesc;

  /// Option label
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get exportQualityHigh;

  /// Option description
  ///
  /// In en, this message translates to:
  /// **'High quality'**
  String get exportQualityHighDesc;

  /// Option label
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get exportQualityMedium;

  /// Option description
  ///
  /// In en, this message translates to:
  /// **'Good for email'**
  String get exportQualityMediumDesc;

  /// Option label
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get exportQualityLow;

  /// Option description
  ///
  /// In en, this message translates to:
  /// **'Smallest file'**
  String get exportQualityLowDesc;

  /// Dialog title
  ///
  /// In en, this message translates to:
  /// **'Merge another document'**
  String get mergeDialogTitle;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'No other documents to merge.'**
  String get mergeDialogEmpty;

  /// App bar
  ///
  /// In en, this message translates to:
  /// **'Recognized text'**
  String get ocrTitle;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t recognize text'**
  String get ocrErrorRecognize;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t export text'**
  String get ocrErrorExport;

  /// Chip; keep ·
  ///
  /// In en, this message translates to:
  /// **'Text layer ready · powers search'**
  String get ocrTextLayerReady;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get ocrCopyText;

  /// Button; keep .txt
  ///
  /// In en, this message translates to:
  /// **'Share .txt'**
  String get ocrShareTxt;

  /// Empty state
  ///
  /// In en, this message translates to:
  /// **'No text recognized on this page yet.'**
  String get ocrEmpty;

  /// Button
  ///
  /// In en, this message translates to:
  /// **'Recognize text'**
  String get ocrRecognizeButton;

  /// Error body
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t open the PDF.'**
  String get pdfPreviewOpenError;

  /// Screen title + settings row
  ///
  /// In en, this message translates to:
  /// **'Send feedback'**
  String get feedbackTitle;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Thanks! Your feedback was sent.'**
  String get feedbackSuccess;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'You\'ve sent a few already — please try again later.'**
  String get feedbackRateLimited;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t verify the app — please try again.'**
  String get feedbackRejectedUnverified;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Check your connection and try again.'**
  String get feedbackOffline;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Please check your message and try again.'**
  String get feedbackInvalid;

  /// Snackbar
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t send right now — please try again.'**
  String get feedbackServerError;

  /// Section label; feedback category
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get feedbackTypeLabel;

  /// Segment
  ///
  /// In en, this message translates to:
  /// **'Bug'**
  String get feedbackTypeBug;

  /// Segment
  ///
  /// In en, this message translates to:
  /// **'Idea'**
  String get feedbackTypeIdea;

  /// Segment
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get feedbackTypeQuestion;

  /// Section label
  ///
  /// In en, this message translates to:
  /// **'Message'**
  String get feedbackMessageLabel;

  /// Text field hint
  ///
  /// In en, this message translates to:
  /// **'Your feedback'**
  String get feedbackMessageHint;

  /// Validator
  ///
  /// In en, this message translates to:
  /// **'Please enter a message'**
  String get feedbackMessageRequired;

  /// Section label
  ///
  /// In en, this message translates to:
  /// **'Email — optional'**
  String get feedbackEmailLabel;

  /// Text field hint
  ///
  /// In en, this message translates to:
  /// **'you@example.com'**
  String get feedbackEmailHint;

  /// Validator
  ///
  /// In en, this message translates to:
  /// **'Enter a valid email or leave it blank'**
  String get feedbackEmailInvalid;

  /// Helper text; keep GitHub
  ///
  /// In en, this message translates to:
  /// **'Optional. This will be publicly visible on GitHub.'**
  String get feedbackEmailPublicNote;

  /// Toggle button
  ///
  /// In en, this message translates to:
  /// **'What will be sent?'**
  String get feedbackDiagnosticsShow;

  /// Toggle button
  ///
  /// In en, this message translates to:
  /// **'Hide what will be sent'**
  String get feedbackDiagnosticsHide;

  /// Box heading
  ///
  /// In en, this message translates to:
  /// **'What we include'**
  String get feedbackDiagnosticsTitle;

  /// Box body
  ///
  /// In en, this message translates to:
  /// **'Diagnostics attached: app version, OS version, device model, and language. No scanned documents or their contents are ever sent.'**
  String get feedbackDiagnosticsBody;

  /// Submit button
  ///
  /// In en, this message translates to:
  /// **'Send report'**
  String get feedbackSubmit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'ar',
    'de',
    'en',
    'es',
    'fr',
    'lb',
    'pt',
    'ru',
    'tr',
    'zh',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'pt':
      {
        switch (locale.countryCode) {
          case 'BR':
            return AppLocalizationsPtBr();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'lb':
      return AppLocalizationsLb();
    case 'pt':
      return AppLocalizationsPt();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
