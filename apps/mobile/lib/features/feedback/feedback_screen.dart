import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/ream_colors.dart';
import '../../theme/widgets/ream_action_button.dart';
import '../../theme/widgets/ream_back_header.dart';
import '../../theme/widgets/ream_section_label.dart';
import '../../theme/widgets/ream_segmented.dart';
import 'feedback_dependencies.dart';
import 'feedback_result.dart';
import 'feedback_service.dart';
import 'turnstile_widget.dart';

/// Localized snackbar message for a [FeedbackResult]. Resolution happens in
/// `build` (via `context.l10n`) since the switch has no `BuildContext` of its
/// own — same pattern as `ExportQualityL10n`.
String _messageFor(FeedbackResult r, AppLocalizations l10n) => switch (r) {
  FeedbackSuccess() || FeedbackDuplicate() => l10n.feedbackSuccess,
  FeedbackRateLimited() => l10n.feedbackRateLimited,
  FeedbackRejectedUnverified() => l10n.feedbackRejectedUnverified,
  FeedbackOffline() => l10n.feedbackOffline,
  FeedbackInvalid() => l10n.feedbackInvalid,
  FeedbackServerError() => l10n.feedbackServerError,
};

class FeedbackScreen extends StatefulWidget {
  final FeedbackDependencies dependencies;

  const FeedbackScreen({
    super.key,
    this.dependencies = const FeedbackDependencies(),
  });

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _message = TextEditingController();
  final _email = TextEditingController();
  String _category = 'bug';
  bool _showDiagnostics = false;
  bool _submitting = false;

  // Set by the Turnstile widget callback (Task 8, device-only); null in host tests.
  String? _turnstileToken;

  late final FeedbackService _service = widget.dependencies.service();

  @override
  void dispose() {
    _message.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      final result = await _service.submit(
        FeedbackDraft(
          category: _category,
          message: _message.text.trim(),
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          turnstileToken: _turnstileToken,
        ),
      );
      if (!mounted) return;
      _showResult(result);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showResult(FeedbackResult r) {
    final msg = _messageFor(r, context.l10n);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (r is FeedbackSuccess || r is FeedbackDuplicate) {
      Navigator.of(context).maybePop();
    }
  }

  InputDecoration _fieldDecoration(ReamColors r, String label) {
    // border and enabledBorder are intentionally identical: this app has no
    // error/focus border style yet, so both fall back to the same neutral
    // r.line outline. border is kept explicit (rather than omitted) so a
    // future error/disabled style has a defined base to diverge from.
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: r.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: r.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: r.line),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: l10n.feedbackTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ReamSectionLabel(l10n.feedbackTypeLabel),
              const SizedBox(height: 8),
              ReamSegmented<String>(
                expanded: true,
                value: _category,
                segments: [
                  ReamSegment(value: 'bug', label: l10n.feedbackTypeBug),
                  ReamSegment(value: 'idea', label: l10n.feedbackTypeIdea),
                  ReamSegment(
                    value: 'question',
                    label: l10n.feedbackTypeQuestion,
                  ),
                ],
                onChanged: (v) => setState(() => _category = v),
              ),
              const SizedBox(height: 16),
              ReamSectionLabel(l10n.feedbackMessageLabel),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('feedback-message'),
                controller: _message,
                maxLines: 5,
                maxLength: 4000,
                style: TextStyle(fontFamily: 'Figtree', color: r.ink),
                decoration: _fieldDecoration(r, l10n.feedbackMessageHint),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.feedbackMessageRequired
                    : null,
              ),
              const SizedBox(height: 16),
              ReamSectionLabel(l10n.feedbackEmailLabel),
              const SizedBox(height: 8),
              TextFormField(
                key: const Key('feedback-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(fontFamily: 'Figtree', color: r.ink),
                decoration: _fieldDecoration(r, l10n.feedbackEmailHint),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final ok = RegExp(
                    r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                  ).hasMatch(v.trim());
                  return ok ? null : l10n.feedbackEmailInvalid;
                },
              ),
              Padding(
                key: const Key('feedback-email-warning'),
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  l10n.feedbackEmailPublicNote,
                  style: TextStyle(fontSize: 12, color: r.muted),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('feedback-diagnostics-toggle'),
                onPressed: () =>
                    setState(() => _showDiagnostics = !_showDiagnostics),
                child: Text(
                  _showDiagnostics
                      ? l10n.feedbackDiagnosticsHide
                      : l10n.feedbackDiagnosticsShow,
                ),
              ),
              if (_showDiagnostics)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 13,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: r.blueSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: r.blue.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: r.blue,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            l10n.feedbackDiagnosticsTitle,
                            style: const TextStyle(
                              fontFamily: 'Figtree',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.feedbackDiagnosticsBody,
                        style: const TextStyle(
                          fontFamily: 'Figtree',
                          fontSize: 11.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              // Turnstile human-verification widget — rendered on device only.
              // Gated on a non-empty site key: host tests inject FeedbackDependencies
              // with the default FeedbackConfig (String.fromEnvironment → ''), so
              // this branch is never entered in the host suite, keeping widget tests
              // free of WebView dependencies.
              if (widget.dependencies.config.turnstileSiteKey.isNotEmpty)
                TurnstileWidget(
                  siteKey: widget.dependencies.config.turnstileSiteKey,
                  baseUrl: () {
                    final url = widget.dependencies.config.workerUrl;
                    if (url.isEmpty) return 'https://localhost';
                    final u = Uri.parse(url);
                    return '${u.scheme}://${u.host}';
                  }(),
                  onToken: (t) => setState(() => _turnstileToken = t),
                ),
              if (widget.dependencies.config.turnstileSiteKey.isNotEmpty)
                const SizedBox(height: 12),
              _submitting
                  ? SizedBox(
                      key: const Key('feedback-submit'),
                      width: double.infinity,
                      height: 52,
                      child: Material(
                        color: r.ink,
                        borderRadius: BorderRadius.circular(15),
                        child: Center(
                          child: SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                ThemeData.estimateBrightnessForColor(r.ink) ==
                                        Brightness.dark
                                    ? Colors.white
                                    : const Color(0xFF201C16),
                              ),
                            ),
                          ),
                        ),
                      ),
                    )
                  : ReamActionButton(
                      key: const Key('feedback-submit'),
                      label: l10n.feedbackSubmit,
                      primary: true,
                      fillColor: r.ink,
                      onPressed: _submit,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
