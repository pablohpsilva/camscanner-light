import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// A self-contained Cloudflare Turnstile widget backed by [webview_flutter].
///
/// Renders the Turnstile implicit challenge in a sandboxed WebView.
/// [onToken] is called with the solved token string on success, or with
/// `null` on error or expiry — callers should gate submission on a non-null
/// token.
///
/// The widget is only ever instantiated when a non-empty [siteKey] is provided
/// (the gate lives in [FeedbackScreen]), so it never appears in host tests.
class TurnstileWidget extends StatefulWidget {
  final String siteKey;

  /// The origin registered in the Turnstile dashboard.  Typically derived from
  /// the worker URL: `'${scheme}://${host}'`.
  final String baseUrl;

  final ValueChanged<String?> onToken;

  const TurnstileWidget({
    super.key,
    required this.siteKey,
    required this.baseUrl,
    required this.onToken,
  });

  @override
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'TurnstileToken',
        onMessageReceived: (m) => widget.onToken(m.message),
      )
      ..addJavaScriptChannel(
        'TurnstileError',
        onMessageReceived: (_) => widget.onToken(null),
      )
      ..loadHtmlString(buildTurnstileHtml(widget.siteKey), baseUrl: widget.baseUrl);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: 72, child: WebViewWidget(controller: _controller));
  }
}

/// Turnstile site keys are Cloudflare identifiers drawn only from
/// `[A-Za-z0-9_-]` (e.g. "0x4AAAAAAA…"). Validating against this charset before
/// interpolating the key into the `JavaScriptMode.unrestricted` WebView HTML
/// closes the (build-time-constant, low-risk) raw-interpolation hole (P14 SF-3):
/// a misconfigured key with any other character is dropped rather than injected.
@visibleForTesting
bool isValidTurnstileSiteKey(String siteKey) =>
    RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(siteKey);

@visibleForTesting
String buildTurnstileHtml(String siteKey) {
  final safeKey = isValidTurnstileSiteKey(siteKey) ? siteKey : '';
  return '''<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    html, body { margin: 0; padding: 0; background: transparent; }
  </style>
</head>
<body>
  <div class="cf-turnstile"
       data-sitekey="$safeKey"
       data-callback="onOk"
       data-error-callback="onErr"
       data-expired-callback="onExp">
  </div>
  <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script>
  <script>
    function onOk(t)  { TurnstileToken.postMessage(t); }
    function onErr()  { TurnstileError.postMessage('error'); }
    function onExp()  { TurnstileError.postMessage('expired'); }
  </script>
</body>
</html>''';
}
