import 'package:flutter/material.dart';

/// Collapses the copy-pasted
/// `ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)))`
/// error-toast boilerplate to one call (P06 task 1). Byte-identical to the sites
/// it replaces — same `SnackBar(content: Text(message))`, no extra styling — so
/// swapping call sites in is behavior-preserving.
extension ErrorSnack on BuildContext {
  void showErrorSnack(String message) {
    ScaffoldMessenger.of(this).showSnackBar(SnackBar(content: Text(message)));
  }
}
