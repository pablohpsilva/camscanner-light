// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonRetry => 'Reintentar';

  @override
  String get commonRetake => 'Repetir';

  @override
  String get commonShare => 'Compartir';

  @override
  String get commonRename => 'Renombrar';

  @override
  String get commonCopied => 'Copiado';

  @override
  String get commonDocumentOptions => 'Opciones del documento';

  @override
  String get commonSearchHint => 'Buscar títulos y texto dentro de las páginas';

  @override
  String commonPageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return '$_temp0';
  }

  @override
  String get commonErrorSaveDocument =>
      'No se pudo guardar el documento. Inténtalo de nuevo.';

  @override
  String get commonErrorRename => 'No se pudo renombrar';

  @override
  String get commonErrorShare => 'No se pudo compartir';

  @override
  String get homeDocumentsTitle => 'Documentos';

  @override
  String get homePrivateOnDevice => 'Privado · en este dispositivo';

  @override
  String get homeCancelSelectionTooltip => 'Cancelar selección';

  @override
  String homeSelectedCount(int count) {
    return '$count seleccionados';
  }

  @override
  String get homeExportTooltip => 'Exportar';

  @override
  String get homeActionScan => 'Escanear';

  @override
  String get homeActionIdCard => 'Carné de identidad';

  @override
  String get homeActionImport => 'Importar';

  @override
  String homeSearchNoMatch(String query) {
    return 'Ningún documento coincide con \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments => 'No se pudieron cargar los documentos.';

  @override
  String get homeErrorImportPhoto => 'No se pudo importar la foto';

  @override
  String get homeViewList => 'Lista';

  @override
  String get homeViewGrid => 'Cuadrícula';

  @override
  String get homeEmptyTitle => 'Aún no hay documentos';

  @override
  String get homeEmptySubtitle =>
      'Toca Escanear para crear tu primer documento';

  @override
  String get sortName => 'Nombre';

  @override
  String get sortCreated => 'Creación';

  @override
  String get sortModified => 'Modificación';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsSectionAppearance => 'Apariencia';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Oscuro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Predeterminado del sistema';

  @override
  String get settingsSectionFeedback => 'Comentarios y ayuda';

  @override
  String get settingsSupportApp => 'Apoya la app';

  @override
  String get settingsAboutTagline =>
      'Tus escaneos permanecen en tu dispositivo: sin cuenta, sin nube.';

  @override
  String get donationHeadline => 'Sin cuentas. Sin nube.\\nSin suscripción.';

  @override
  String get donationDisclaimer =>
      'Esto es solo una donación voluntaria. No recibes funciones, ventajas ni contenido a cambio: simplemente ayuda a mantener el desarrollo.';

  @override
  String get donationOptionalNote =>
      'Donar no desbloquea nada: todas las funciones ya son tuyas. Esto es totalmente opcional.';

  @override
  String get donationKofiButton => 'Invítame a un café — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'No se pudo abrir Ko-fi';

  @override
  String get donationBitcoinCopied => 'Dirección de Bitcoin copiada';

  @override
  String get donationBitcoinHeading => 'O dona con Bitcoin';

  @override
  String get donationCopyAddress => 'Copiar dirección';

  @override
  String get donationBannerText => '¿Te gusta la app? Toca para apoyarla';

  @override
  String get scanTitle => 'Escanear';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas guardadas',
      one: '1 página guardada',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'No se pudo reemplazar la página. Inténtalo de nuevo.';

  @override
  String get scanSaveFailed => 'No se pudo guardar el escaneo.';

  @override
  String get idScanTitle => 'Escanear ID';

  @override
  String get idScanFrontPrompt => 'Escanea el FRENTE del documento';

  @override
  String get idScanBackPrompt => 'Escanea el REVERSO del documento';

  @override
  String get idScanSaving => 'Guardando…';

  @override
  String get idScanErrorSave =>
      'No se pudo guardar el documento. Inténtalo de nuevo.';

  @override
  String get idScanErrorBackRetake =>
      'Se guardó el frente, pero el reverso falló. Repítelo desde el documento.';

  @override
  String get captureReviewTitle => 'Revisión';

  @override
  String get captureReviewReset => 'Restablecer';

  @override
  String get captureReviewAccept => 'Aceptar';

  @override
  String get editFilterTitle => 'Filtro';

  @override
  String get editCropTitle => 'Revisar y limpiar';

  @override
  String get filterAuto => 'Automático';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Color';

  @override
  String get filterGrayscale => 'Escala de grises';

  @override
  String get toolbarCrop => 'Recortar';

  @override
  String get toolbarRotate => 'Girar';

  @override
  String get toolbarFilter => 'Filtro';

  @override
  String get toolbarText => 'Texto';

  @override
  String get cropHandleTopEdge => 'Punto medio del borde superior';

  @override
  String get cropHandleRightEdge => 'Punto medio del borde derecho';

  @override
  String get cropHandleBottomEdge => 'Punto medio del borde inferior';

  @override
  String get cropHandleLeftEdge => 'Punto medio del borde izquierdo';

  @override
  String get cropHandleTopLeft => 'Esquina de recorte superior izquierda';

  @override
  String get cropHandleTopRight => 'Esquina de recorte superior derecha';

  @override
  String get cropHandleBottomRight => 'Esquina de recorte inferior derecha';

  @override
  String get cropHandleBottomLeft => 'Esquina de recorte inferior izquierda';

  @override
  String get viewerDeleteDocumentConfirm =>
      '¿Eliminar este documento? Esta acción no se puede deshacer.';

  @override
  String get viewerDeleteDocumentError => 'No se pudo eliminar';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Esta es la única página. Eliminarla borra todo el documento.';

  @override
  String get viewerDeletePageConfirm =>
      '¿Eliminar esta página? Esta acción no se puede deshacer.';

  @override
  String get viewerDeletePageError => 'No se pudo eliminar la página';

  @override
  String get viewerExportPdfError => 'No se pudo exportar el PDF';

  @override
  String get viewerShareImageError => 'No se pudo compartir la imagen';

  @override
  String get viewerShareImagesError => 'No se pudieron compartir las imágenes';

  @override
  String get viewerPrintSuccess => 'Enviado a la impresora';

  @override
  String get viewerPrintError => 'No se pudo imprimir';

  @override
  String get viewerProtectPdfSuccess => 'PDF protegido listo';

  @override
  String get viewerProtectPdfError => 'No se pudo proteger el PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'Esta es la última página, no hay nada que dividir después.';

  @override
  String get viewerSplitSuccess => 'Dividido en un nuevo documento';

  @override
  String get viewerSplitError => 'No se pudo dividir';

  @override
  String get viewerMergeError => 'No se pudo combinar';

  @override
  String get viewerReorderPagesError => 'No se pudieron reordenar las páginas';

  @override
  String get viewerRotateError => 'No se pudo girar';

  @override
  String get viewerCropError => 'No se pudo actualizar el recorte';

  @override
  String get viewerFilterError => 'No se pudo cambiar el filtro';

  @override
  String get viewerLoadError => 'No se pudo cargar este documento.';

  @override
  String get viewerEmptyPages => 'Este documento no tiene páginas.';

  @override
  String get viewerMenuMerge => 'Combinar con otro documento…';

  @override
  String get viewerMenuSplit => 'Dividir después de esta página';

  @override
  String get viewerMenuDeleteDocument => 'Eliminar documento';

  @override
  String get viewerShareExportPdf => 'Exportar PDF';

  @override
  String get viewerShareAsImage => 'Compartir como imagen';

  @override
  String get viewerShareAllAsImages => 'Compartir todo como imágenes';

  @override
  String get viewerSharePrint => 'Imprimir';

  @override
  String get viewerShareProtect => 'Proteger con contraseña';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Compartir enlace';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable =>
      'Compartir por enlace aún no está disponible';

  @override
  String get shareFaxUnavailable => 'El fax aún no está disponible';

  @override
  String get renameDialogTitle => 'Renombrar documento';

  @override
  String get renameFieldLabel => 'Nombre';

  @override
  String get passwordDialogTitle => 'Proteger PDF con contraseña';

  @override
  String get passwordFieldHint => 'Introduce una contraseña';

  @override
  String get passwordProtectButton => 'Proteger';

  @override
  String get exportQualityTitle => 'Calidad de exportación';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Calidad total, archivo más grande';

  @override
  String get exportQualityHigh => 'Alta';

  @override
  String get exportQualityHighDesc => 'Alta calidad';

  @override
  String get exportQualityMedium => 'Media';

  @override
  String get exportQualityMediumDesc => 'Ideal para correo electrónico';

  @override
  String get exportQualityLow => 'Baja';

  @override
  String get exportQualityLowDesc => 'Archivo más pequeño';

  @override
  String get mergeDialogTitle => 'Combinar con otro documento';

  @override
  String get mergeDialogEmpty => 'No hay otros documentos para combinar.';

  @override
  String get ocrTitle => 'Texto reconocido';

  @override
  String get ocrErrorRecognize => 'No se pudo reconocer el texto';

  @override
  String get ocrErrorExport => 'No se pudo exportar el texto';

  @override
  String get ocrTextLayerReady => 'Capa de texto lista · habilita la búsqueda';

  @override
  String get ocrCopyText => 'Copiar texto';

  @override
  String get ocrShareTxt => 'Compartir .txt';

  @override
  String get ocrEmpty => 'Aún no se ha reconocido texto en esta página.';

  @override
  String get ocrRecognizeButton => 'Reconocer texto';

  @override
  String get pdfPreviewOpenError => 'No se pudo abrir el PDF.';

  @override
  String get feedbackTitle => 'Enviar comentarios';

  @override
  String get feedbackSuccess => '¡Gracias! Tu comentario se envió.';

  @override
  String get feedbackRateLimited =>
      'Ya has enviado varios: inténtalo de nuevo más tarde.';

  @override
  String get feedbackRejectedUnverified =>
      'No se pudo verificar la app. Inténtalo de nuevo.';

  @override
  String get feedbackOffline => 'Comprueba tu conexión e inténtalo de nuevo.';

  @override
  String get feedbackInvalid => 'Revisa tu mensaje e inténtalo de nuevo.';

  @override
  String get feedbackServerError =>
      'No se pudo enviar en este momento. Inténtalo de nuevo.';

  @override
  String get feedbackTypeLabel => 'Tipo';

  @override
  String get feedbackTypeBug => 'Error';

  @override
  String get feedbackTypeIdea => 'Idea';

  @override
  String get feedbackTypeQuestion => 'Pregunta';

  @override
  String get feedbackMessageLabel => 'Mensaje';

  @override
  String get feedbackMessageHint => 'Tu comentario';

  @override
  String get feedbackMessageRequired => 'Introduce un mensaje';

  @override
  String get feedbackEmailLabel => 'Correo electrónico (opcional)';

  @override
  String get feedbackEmailHint => 'tu@ejemplo.com';

  @override
  String get feedbackEmailInvalid =>
      'Introduce un correo electrónico válido o déjalo en blanco';

  @override
  String get feedbackEmailPublicNote =>
      'Opcional. Será visible públicamente en GitHub.';

  @override
  String get feedbackDiagnosticsShow => '¿Qué se enviará?';

  @override
  String get feedbackDiagnosticsHide => 'Ocultar qué se enviará';

  @override
  String get feedbackDiagnosticsTitle => 'Qué incluimos';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnósticos adjuntos: versión de la app, versión del sistema operativo, modelo del dispositivo e idioma. Nunca se envían los documentos escaneados ni su contenido.';

  @override
  String get feedbackSubmit => 'Enviar informe';
}
