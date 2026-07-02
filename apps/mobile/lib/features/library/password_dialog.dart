import 'package:flutter/material.dart';

/// Prompts for a password (obscured). Resolves to the entered password, or null
/// if cancelled. Protect is disabled until a non-empty password is entered.
Future<String?> showPasswordDialog(BuildContext context) =>
    showDialog<String>(context: context, builder: (_) => const PasswordDialog());

class PasswordDialog extends StatefulWidget {
  const PasswordDialog({super.key});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canConfirm = _controller.text.trim().isNotEmpty;
    return AlertDialog(
      key: const Key('password-dialog'),
      title: const Text('Password-protect PDF'),
      content: TextField(
        key: const Key('password-field'),
        controller: _controller,
        autofocus: true,
        obscureText: true,
        decoration: const InputDecoration(hintText: 'Enter a password'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (v) {
          if (v.trim().isNotEmpty) Navigator.of(context).pop(v);
        },
      ),
      actions: [
        TextButton(
          key: const Key('password-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('password-confirm'),
          onPressed:
              canConfirm ? () => Navigator.of(context).pop(_controller.text) : null,
          child: const Text('Protect'),
        ),
      ],
    );
  }
}
