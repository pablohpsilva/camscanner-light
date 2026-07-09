import 'package:flutter/material.dart';

import 'feedback_dependencies.dart';
import 'feedback_result.dart';
import 'feedback_service.dart';

class FeedbackScreen extends StatefulWidget {
  final FeedbackDependencies dependencies;

  const FeedbackScreen(
      {super.key, this.dependencies = const FeedbackDependencies()});

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
      final result = await _service.submit(FeedbackDraft(
        category: _category,
        message: _message.text.trim(),
        email: _email.text.trim().isEmpty ? null : _email.text.trim(),
        turnstileToken: _turnstileToken,
      ));
      if (!mounted) return;
      _showResult(result);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showResult(FeedbackResult r) {
    final msg = switch (r) {
      FeedbackSuccess() || FeedbackDuplicate() => 'Thanks! Your feedback was sent.',
      FeedbackRateLimited() => "You've sent a few already — please try again later.",
      FeedbackRejectedUnverified() => "Couldn't verify the app — please try again.",
      FeedbackOffline() => 'Check your connection and try again.',
      FeedbackInvalid() => 'Please check your message and try again.',
      FeedbackServerError() => "Couldn't send right now — please try again.",
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    if (r is FeedbackSuccess || r is FeedbackDuplicate) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send feedback')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: const Key('feedback-category'),
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Type'),
                items: const [
                  DropdownMenuItem(value: 'bug', child: Text('Bug')),
                  DropdownMenuItem(value: 'idea', child: Text('Idea')),
                  DropdownMenuItem(value: 'question', child: Text('Question')),
                ],
                onChanged: (v) => setState(() => _category = v ?? 'bug'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('feedback-message'),
                controller: _message,
                maxLines: 5,
                maxLength: 4000,
                decoration: const InputDecoration(
                  labelText: 'Your feedback',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Please enter a message' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const Key('feedback-email'),
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  border: OutlineInputBorder(),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final ok =
                      RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v.trim());
                  return ok ? null : 'Enter a valid email or leave it blank';
                },
              ),
              const Padding(
                key: Key('feedback-email-warning'),
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'Optional. This will be publicly visible on GitHub.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                key: const Key('feedback-diagnostics-toggle'),
                onPressed: () =>
                    setState(() => _showDiagnostics = !_showDiagnostics),
                child: Text(
                  _showDiagnostics ? 'Hide what will be sent' : 'What will be sent?',
                ),
              ),
              if (_showDiagnostics)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'Diagnostics attached: app version, OS version, device model, and language. '
                    'No scanned documents or their contents are ever sent.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const Key('feedback-submit'),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Send'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
