// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonDelete => 'Eliminar';

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonRetake => 'Repetir';

  @override
  String get commonShare => 'Partilhar';

  @override
  String get commonRename => 'Mudar o nome';

  @override
  String get commonCopied => 'Copiado';

  @override
  String get commonDocumentOptions => 'Opções do documento';

  @override
  String get commonSearchHint => 'Pesquisar títulos e texto nas páginas';

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
      'Não foi possível guardar o documento. Tente novamente.';

  @override
  String get commonErrorRename => 'Não foi possível mudar o nome';

  @override
  String get commonErrorShare => 'Não foi possível partilhar';

  @override
  String get homeDocumentsTitle => 'Documentos';

  @override
  String get homePrivateOnDevice => 'Privado · neste dispositivo';

  @override
  String get homeCancelSelectionTooltip => 'Cancelar seleção';

  @override
  String homeSelectedCount(int count) {
    return '$count selecionados';
  }

  @override
  String get homeExportTooltip => 'Exportar';

  @override
  String get homeActionScan => 'Digitalizar';

  @override
  String get homeActionIdCard => 'Cartão de identificação';

  @override
  String get homeActionImport => 'Importar';

  @override
  String homeSearchNoMatch(String query) {
    return 'Nenhum documento corresponde a \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments =>
      'Não foi possível carregar os documentos.';

  @override
  String get homeErrorImportPhoto => 'Não foi possível importar a foto';

  @override
  String get homeViewList => 'Lista';

  @override
  String get homeViewGrid => 'Grelha';

  @override
  String get homeEmptyTitle => 'Ainda sem documentos';

  @override
  String get homeEmptySubtitle =>
      'Toque em Digitalizar para criar o seu primeiro documento';

  @override
  String get sortName => 'Nome';

  @override
  String get sortCreated => 'Criado';

  @override
  String get sortModified => 'Modificado';

  @override
  String get settingsTitle => 'Definições';

  @override
  String get settingsSectionAppearance => 'Aparência';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Predefinição do sistema';

  @override
  String get settingsSectionFeedback => 'Comentários e suporte';

  @override
  String get settingsSupportApp => 'Apoiar a aplicação';

  @override
  String get settingsAboutTagline =>
      'As suas digitalizações ficam no seu dispositivo — sem conta, sem nuvem.';

  @override
  String get donationHeadline => 'Sem contas. Sem nuvem.\\nSem subscrição.';

  @override
  String get donationDisclaimer =>
      'Isto é apenas um donativo voluntário. Não recebe funcionalidades, benefícios ou conteúdos em troca — apenas ajuda a apoiar o desenvolvimento contínuo.';

  @override
  String get donationOptionalNote =>
      'Doar não desbloqueia nada — todas as funcionalidades já são suas. Isto é genuinamente opcional.';

  @override
  String get donationKofiButton => 'Ofereça-me um café — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Não foi possível abrir o Ko-fi';

  @override
  String get donationBitcoinCopied => 'Endereço Bitcoin copiado';

  @override
  String get donationBitcoinHeading => 'Ou doe com Bitcoin';

  @override
  String get donationCopyAddress => 'Copiar endereço';

  @override
  String get donationBannerText => 'A gostar da aplicação? Toque para a apoiar';

  @override
  String get scanTitle => 'Digitalizar';

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
      'Não foi possível substituir a página. Tente novamente.';

  @override
  String get scanSaveFailed => 'Não foi possível guardar a digitalização.';

  @override
  String get idScanTitle => 'Digitalizar identificação';

  @override
  String get idScanFrontPrompt => 'Digitalize a FRENTE do cartão';

  @override
  String get idScanBackPrompt => 'Digitalize o VERSO do cartão';

  @override
  String get idScanSaving => 'A guardar…';

  @override
  String get idScanErrorSave =>
      'Não foi possível guardar a identificação. Tente novamente.';

  @override
  String get idScanErrorBackRetake =>
      'A frente foi guardada, mas o verso falhou. Repita-o a partir do documento.';

  @override
  String get captureReviewTitle => 'Rever';

  @override
  String get captureReviewReset => 'Repor';

  @override
  String get captureReviewAccept => 'Aceitar';

  @override
  String get editFilterTitle => 'Filtro';

  @override
  String get editCropTitle => 'Rever e limpar';

  @override
  String get filterAuto => 'Automático';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Cor';

  @override
  String get filterGrayscale => 'Escala de cinzentos';

  @override
  String get toolbarCrop => 'Recortar';

  @override
  String get toolbarRotate => 'Rodar';

  @override
  String get toolbarFilter => 'Filtro';

  @override
  String get toolbarText => 'Texto';

  @override
  String get cropHandleTopEdge => 'Ponto médio do limite superior';

  @override
  String get cropHandleRightEdge => 'Ponto médio do limite direito';

  @override
  String get cropHandleBottomEdge => 'Ponto médio do limite inferior';

  @override
  String get cropHandleLeftEdge => 'Ponto médio do limite esquerdo';

  @override
  String get cropHandleTopLeft => 'Canto superior esquerdo do recorte';

  @override
  String get cropHandleTopRight => 'Canto superior direito do recorte';

  @override
  String get cropHandleBottomRight => 'Canto inferior direito do recorte';

  @override
  String get cropHandleBottomLeft => 'Canto inferior esquerdo do recorte';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Eliminar este documento? Esta ação não pode ser anulada.';

  @override
  String get viewerDeleteDocumentError => 'Não foi possível eliminar';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Esta é a única página. Eliminá-la remove o documento inteiro.';

  @override
  String get viewerDeletePageConfirm =>
      'Eliminar esta página? Esta ação não pode ser anulada.';

  @override
  String get viewerDeletePageError => 'Não foi possível eliminar a página';

  @override
  String get viewerExportPdfError => 'Não foi possível exportar o PDF';

  @override
  String get viewerShareImageError => 'Não foi possível partilhar a imagem';

  @override
  String get viewerShareImagesError => 'Não foi possível partilhar as imagens';

  @override
  String get viewerPrintSuccess => 'Enviado para a impressora';

  @override
  String get viewerPrintError => 'Não foi possível imprimir';

  @override
  String get viewerProtectPdfSuccess => 'PDF protegido pronto';

  @override
  String get viewerProtectPdfError => 'Não foi possível proteger o PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'Esta é a última página — não há nada para dividir a seguir.';

  @override
  String get viewerSplitSuccess => 'Dividido num novo documento';

  @override
  String get viewerSplitError => 'Não foi possível dividir';

  @override
  String get viewerMergeError => 'Não foi possível unir';

  @override
  String get viewerReorderPagesError => 'Não foi possível reordenar as páginas';

  @override
  String get viewerRotateError => 'Não foi possível rodar';

  @override
  String get viewerCropError => 'Não foi possível atualizar o recorte';

  @override
  String get viewerFilterError => 'Não foi possível alterar o filtro';

  @override
  String get viewerLoadError => 'Não foi possível carregar este documento.';

  @override
  String get viewerEmptyPages => 'Este documento não tem páginas.';

  @override
  String get viewerMenuMerge => 'Unir outro documento…';

  @override
  String get viewerMenuSplit => 'Dividir depois desta página';

  @override
  String get viewerMenuDeleteDocument => 'Eliminar documento';

  @override
  String get viewerShareExportPdf => 'Exportar PDF';

  @override
  String get viewerShareAsImage => 'Partilhar como imagem';

  @override
  String get viewerShareAllAsImages => 'Partilhar tudo como imagens';

  @override
  String get viewerSharePrint => 'Imprimir';

  @override
  String get viewerShareProtect => 'Proteger com palavra-passe';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Partilhar ligação';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable =>
      'A partilha por ligação ainda não está disponível';

  @override
  String get shareFaxUnavailable => 'O fax ainda não está disponível';

  @override
  String get renameDialogTitle => 'Mudar o nome do documento';

  @override
  String get renameFieldLabel => 'Nome';

  @override
  String get passwordDialogTitle => 'Proteger PDF com palavra-passe';

  @override
  String get passwordFieldHint => 'Introduza uma palavra-passe';

  @override
  String get passwordProtectButton => 'Proteger';

  @override
  String get exportQualityTitle => 'Qualidade de exportação';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Qualidade total, ficheiro maior';

  @override
  String get exportQualityHigh => 'Alta';

  @override
  String get exportQualityHighDesc => 'Alta qualidade';

  @override
  String get exportQualityMedium => 'Média';

  @override
  String get exportQualityMediumDesc => 'Boa para email';

  @override
  String get exportQualityLow => 'Baixa';

  @override
  String get exportQualityLowDesc => 'Ficheiro mais pequeno';

  @override
  String get mergeDialogTitle => 'Unir outro documento';

  @override
  String get mergeDialogEmpty => 'Não há outros documentos para unir.';

  @override
  String get ocrTitle => 'Texto reconhecido';

  @override
  String get ocrErrorRecognize => 'Não foi possível reconhecer o texto';

  @override
  String get ocrErrorExport => 'Não foi possível exportar o texto';

  @override
  String get ocrTextLayerReady => 'Camada de texto pronta · melhora a pesquisa';

  @override
  String get ocrCopyText => 'Copiar texto';

  @override
  String get ocrShareTxt => 'Partilhar .txt';

  @override
  String get ocrEmpty => 'Ainda não foi reconhecido texto nesta página.';

  @override
  String get ocrRecognizeButton => 'Reconhecer texto';

  @override
  String get pdfPreviewOpenError => 'Não foi possível abrir o PDF.';

  @override
  String get feedbackTitle => 'Enviar comentários';

  @override
  String get feedbackSuccess => 'Obrigado! Os seus comentários foram enviados.';

  @override
  String get feedbackRateLimited =>
      'Já enviou alguns comentários — tente novamente mais tarde.';

  @override
  String get feedbackRejectedUnverified =>
      'Não foi possível verificar a aplicação — tente novamente.';

  @override
  String get feedbackOffline => 'Verifique a sua ligação e tente novamente.';

  @override
  String get feedbackInvalid => 'Verifique a sua mensagem e tente novamente.';

  @override
  String get feedbackServerError =>
      'Não foi possível enviar agora — tente novamente.';

  @override
  String get feedbackTypeLabel => 'Tipo';

  @override
  String get feedbackTypeBug => 'Erro';

  @override
  String get feedbackTypeIdea => 'Ideia';

  @override
  String get feedbackTypeQuestion => 'Pergunta';

  @override
  String get feedbackMessageLabel => 'Mensagem';

  @override
  String get feedbackMessageHint => 'O seu comentário';

  @override
  String get feedbackMessageRequired => 'Introduza uma mensagem';

  @override
  String get feedbackEmailLabel => 'Email — opcional';

  @override
  String get feedbackEmailHint => 'voce@exemplo.com';

  @override
  String get feedbackEmailInvalid =>
      'Introduza um email válido ou deixe em branco';

  @override
  String get feedbackEmailPublicNote =>
      'Opcional. Isto ficará publicamente visível no GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'O que vai ser enviado?';

  @override
  String get feedbackDiagnosticsHide => 'Ocultar o que vai ser enviado';

  @override
  String get feedbackDiagnosticsTitle => 'O que incluímos';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnósticos anexados: versão da aplicação, versão do sistema operativo, modelo do dispositivo e idioma. Nunca são enviados documentos digitalizados nem o seu conteúdo.';

  @override
  String get feedbackSubmit => 'Enviar relatório';
}

/// The translations for Portuguese, as used in Brazil (`pt_BR`).
class AppLocalizationsPtBr extends AppLocalizationsPt {
  AppLocalizationsPtBr() : super('pt_BR');

  @override
  String get appTitle => 'CamScanner-light';

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonDelete => 'Excluir';

  @override
  String get commonRetry => 'Tentar novamente';

  @override
  String get commonRetake => 'Refazer';

  @override
  String get commonShare => 'Compartilhar';

  @override
  String get commonRename => 'Renomear';

  @override
  String get commonCopied => 'Copiado';

  @override
  String get commonDocumentOptions => 'Opções do documento';

  @override
  String get commonSearchHint => 'Buscar títulos e texto nas páginas';

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
      'Não foi possível salvar o documento. Tente novamente.';

  @override
  String get commonErrorRename => 'Não foi possível renomear';

  @override
  String get commonErrorShare => 'Não foi possível compartilhar';

  @override
  String get homeDocumentsTitle => 'Documentos';

  @override
  String get homePrivateOnDevice => 'Privado · neste dispositivo';

  @override
  String get homeCancelSelectionTooltip => 'Cancelar seleção';

  @override
  String homeSelectedCount(int count) {
    return '$count selecionado(s)';
  }

  @override
  String get homeExportTooltip => 'Exportar';

  @override
  String get homeActionScan => 'Digitalizar';

  @override
  String get homeActionIdCard => 'Documento de identidade';

  @override
  String get homeActionImport => 'Importar';

  @override
  String homeSearchNoMatch(String query) {
    return 'Nenhum documento corresponde a \"$query\".';
  }

  @override
  String get homeErrorLoadDocuments =>
      'Não foi possível carregar os documentos.';

  @override
  String get homeErrorImportPhoto => 'Não foi possível importar a foto';

  @override
  String get homeViewList => 'Lista';

  @override
  String get homeViewGrid => 'Grade';

  @override
  String get homeEmptyTitle => 'Nenhum documento ainda';

  @override
  String get homeEmptySubtitle =>
      'Toque em Digitalizar para criar seu primeiro documento';

  @override
  String get sortName => 'Nome';

  @override
  String get sortCreated => 'Criado';

  @override
  String get sortModified => 'Modificado';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsSectionAppearance => 'Aparência';

  @override
  String get settingsThemeLight => 'Claro';

  @override
  String get settingsThemeDark => 'Escuro';

  @override
  String get settingsThemeSystem => 'Sistema';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsLanguageSystem => 'Padrão do sistema';

  @override
  String get settingsSectionFeedback => 'Feedback e suporte';

  @override
  String get settingsSupportApp => 'Apoiar o app';

  @override
  String get settingsAboutTagline =>
      'Seus documentos digitalizados ficam no seu dispositivo — sem conta, sem nuvem.';

  @override
  String get donationHeadline => 'Sem contas. Sem nuvem.\\nSem assinatura.';

  @override
  String get donationDisclaimer =>
      'Esta é apenas uma doação voluntária. Você não recebe nenhum recurso, benefício ou conteúdo em troca — ela apenas ajuda a apoiar o desenvolvimento contínuo.';

  @override
  String get donationOptionalNote =>
      'Doar não desbloqueia nada — todos os recursos já são seus. Isso é realmente opcional.';

  @override
  String get donationKofiButton => 'Pague um café — Ko-fi';

  @override
  String get donationErrorOpenKofi => 'Não foi possível abrir o Ko-fi';

  @override
  String get donationBitcoinCopied => 'Endereço de Bitcoin copiado';

  @override
  String get donationBitcoinHeading => 'Ou doe com Bitcoin';

  @override
  String get donationCopyAddress => 'Copiar endereço';

  @override
  String get donationBannerText => 'Está gostando do app? Toque para apoiar';

  @override
  String get scanTitle => 'Digitalizar';

  @override
  String scanPagesSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas salvas',
      one: '1 página salva',
    );
    return '$_temp0';
  }

  @override
  String get scanErrorReplacePage =>
      'Não foi possível substituir a página. Tente novamente.';

  @override
  String get scanSaveFailed => 'Não foi possível salvar a digitalização.';

  @override
  String get idScanTitle => 'Digitalizar documento';

  @override
  String get idScanFrontPrompt => 'Digitalize a FRENTE do documento';

  @override
  String get idScanBackPrompt => 'Digitalize o VERSO do documento';

  @override
  String get idScanSaving => 'Salvando…';

  @override
  String get idScanErrorSave =>
      'Não foi possível salvar o documento. Tente novamente.';

  @override
  String get idScanErrorBackRetake =>
      'A frente foi salva, mas o verso falhou. Refaça-o a partir do documento.';

  @override
  String get captureReviewTitle => 'Revisar';

  @override
  String get captureReviewReset => 'Redefinir';

  @override
  String get captureReviewAccept => 'Aceitar';

  @override
  String get editFilterTitle => 'Filtro';

  @override
  String get editCropTitle => 'Revisar e ajustar';

  @override
  String get filterAuto => 'Automático';

  @override
  String get filterOriginal => 'Original';

  @override
  String get filterColor => 'Cor';

  @override
  String get filterGrayscale => 'Tons de cinza';

  @override
  String get toolbarCrop => 'Cortar';

  @override
  String get toolbarRotate => 'Girar';

  @override
  String get toolbarFilter => 'Filtro';

  @override
  String get toolbarText => 'Texto';

  @override
  String get cropHandleTopEdge => 'Ponto médio da borda superior';

  @override
  String get cropHandleRightEdge => 'Ponto médio da borda direita';

  @override
  String get cropHandleBottomEdge => 'Ponto médio da borda inferior';

  @override
  String get cropHandleLeftEdge => 'Ponto médio da borda esquerda';

  @override
  String get cropHandleTopLeft => 'Canto de corte superior esquerdo';

  @override
  String get cropHandleTopRight => 'Canto de corte superior direito';

  @override
  String get cropHandleBottomRight => 'Canto de corte inferior direito';

  @override
  String get cropHandleBottomLeft => 'Canto de corte inferior esquerdo';

  @override
  String get viewerDeleteDocumentConfirm =>
      'Excluir este documento? Essa ação não pode ser desfeita.';

  @override
  String get viewerDeleteDocumentError => 'Não foi possível excluir';

  @override
  String get viewerDeletePageOnlyPageWarning =>
      'Esta é a única página. Excluí-la remove o documento inteiro.';

  @override
  String get viewerDeletePageConfirm =>
      'Excluir esta página? Essa ação não pode ser desfeita.';

  @override
  String get viewerDeletePageError => 'Não foi possível excluir a página';

  @override
  String get viewerExportPdfError => 'Não foi possível exportar o PDF';

  @override
  String get viewerShareImageError => 'Não foi possível compartilhar a imagem';

  @override
  String get viewerShareImagesError =>
      'Não foi possível compartilhar as imagens';

  @override
  String get viewerPrintSuccess => 'Enviado para a impressora';

  @override
  String get viewerPrintError => 'Não foi possível imprimir';

  @override
  String get viewerProtectPdfSuccess => 'PDF protegido pronto';

  @override
  String get viewerProtectPdfError => 'Não foi possível proteger o PDF';

  @override
  String get viewerSplitLastPageWarning =>
      'Esta é a última página — não há nada para dividir depois dela.';

  @override
  String get viewerSplitSuccess => 'Dividido em um novo documento';

  @override
  String get viewerSplitError => 'Não foi possível dividir';

  @override
  String get viewerMergeError => 'Não foi possível mesclar';

  @override
  String get viewerReorderPagesError => 'Não foi possível reordenar as páginas';

  @override
  String get viewerRotateError => 'Não foi possível girar';

  @override
  String get viewerCropError => 'Não foi possível atualizar o corte';

  @override
  String get viewerFilterError => 'Não foi possível alterar o filtro';

  @override
  String get viewerLoadError => 'Não foi possível carregar este documento.';

  @override
  String get viewerEmptyPages => 'Este documento não tem páginas.';

  @override
  String get viewerMenuMerge => 'Mesclar outro documento…';

  @override
  String get viewerMenuSplit => 'Dividir após esta página';

  @override
  String get viewerMenuDeleteDocument => 'Excluir documento';

  @override
  String get viewerShareExportPdf => 'Exportar PDF';

  @override
  String get viewerShareAsImage => 'Compartilhar como imagem';

  @override
  String get viewerShareAllAsImages => 'Compartilhar tudo como imagens';

  @override
  String get viewerSharePrint => 'Imprimir';

  @override
  String get viewerShareProtect => 'Proteger com senha';

  @override
  String viewerPageCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get shareLink => 'Compartilhar link';

  @override
  String get shareFax => 'Fax';

  @override
  String get shareLinkUnavailable =>
      'O compartilhamento por link ainda não está disponível';

  @override
  String get shareFaxUnavailable => 'O fax ainda não está disponível';

  @override
  String get renameDialogTitle => 'Renomear documento';

  @override
  String get renameFieldLabel => 'Nome';

  @override
  String get passwordDialogTitle => 'Proteger PDF com senha';

  @override
  String get passwordFieldHint => 'Digite uma senha';

  @override
  String get passwordProtectButton => 'Proteger';

  @override
  String get exportQualityTitle => 'Qualidade de exportação';

  @override
  String get exportQualityOriginal => 'Original';

  @override
  String get exportQualityOriginalDesc => 'Qualidade total, arquivo maior';

  @override
  String get exportQualityHigh => 'Alta';

  @override
  String get exportQualityHighDesc => 'Alta qualidade';

  @override
  String get exportQualityMedium => 'Média';

  @override
  String get exportQualityMediumDesc => 'Boa para e-mail';

  @override
  String get exportQualityLow => 'Baixa';

  @override
  String get exportQualityLowDesc => 'Arquivo menor';

  @override
  String get mergeDialogTitle => 'Mesclar outro documento';

  @override
  String get mergeDialogEmpty => 'Nenhum outro documento para mesclar.';

  @override
  String get ocrTitle => 'Texto reconhecido';

  @override
  String get ocrErrorRecognize => 'Não foi possível reconhecer o texto';

  @override
  String get ocrErrorExport => 'Não foi possível exportar o texto';

  @override
  String get ocrTextLayerReady => 'Camada de texto pronta · alimenta a busca';

  @override
  String get ocrCopyText => 'Copiar texto';

  @override
  String get ocrShareTxt => 'Compartilhar .txt';

  @override
  String get ocrEmpty => 'Nenhum texto reconhecido nesta página ainda.';

  @override
  String get ocrRecognizeButton => 'Reconhecer texto';

  @override
  String get pdfPreviewOpenError => 'Não foi possível abrir o PDF.';

  @override
  String get feedbackTitle => 'Enviar feedback';

  @override
  String get feedbackSuccess => 'Obrigado! Seu feedback foi enviado.';

  @override
  String get feedbackRateLimited =>
      'Você já enviou alguns — tente novamente mais tarde.';

  @override
  String get feedbackRejectedUnverified =>
      'Não foi possível verificar o app — tente novamente.';

  @override
  String get feedbackOffline => 'Verifique sua conexão e tente novamente.';

  @override
  String get feedbackInvalid => 'Verifique sua mensagem e tente novamente.';

  @override
  String get feedbackServerError =>
      'Não foi possível enviar agora — tente novamente.';

  @override
  String get feedbackTypeLabel => 'Tipo';

  @override
  String get feedbackTypeBug => 'Bug';

  @override
  String get feedbackTypeIdea => 'Ideia';

  @override
  String get feedbackTypeQuestion => 'Pergunta';

  @override
  String get feedbackMessageLabel => 'Mensagem';

  @override
  String get feedbackMessageHint => 'Seu feedback';

  @override
  String get feedbackMessageRequired => 'Digite uma mensagem';

  @override
  String get feedbackEmailLabel => 'E-mail — opcional';

  @override
  String get feedbackEmailHint => 'voce@exemplo.com';

  @override
  String get feedbackEmailInvalid =>
      'Digite um e-mail válido ou deixe em branco';

  @override
  String get feedbackEmailPublicNote =>
      'Opcional. Ficará publicamente visível no GitHub.';

  @override
  String get feedbackDiagnosticsShow => 'O que será enviado?';

  @override
  String get feedbackDiagnosticsHide => 'Ocultar o que será enviado';

  @override
  String get feedbackDiagnosticsTitle => 'O que incluímos';

  @override
  String get feedbackDiagnosticsBody =>
      'Diagnósticos incluídos: versão do app, versão do sistema, modelo do dispositivo e idioma. Nenhum documento digitalizado ou seu conteúdo é enviado.';

  @override
  String get feedbackSubmit => 'Enviar relatório';
}
