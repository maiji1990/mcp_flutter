## 0.1.0 — unreleased (fork)

### Added

- `ReleaseWebViewRegistry`: explicit registration of app-owned WebViews with an
  exact origin allow-list (HTTPS by default, `allowHttp` for staging) and a
  per-view `ReleaseWebPrivacyPolicy`.
- `WebViewDomReleaseSource`: `ReleaseEmbeddedWebSource` over the registry, with
  navigation epochs, per-script timeouts, result-size caps, and DNS-free origin
  checks.
- Fixed DOM scripts: a bounded snapshot walk (interactive elements only,
  password/payment/OTP redaction, no cookies/storage/HTML) and click/set-text/
  scroll actions that validate origin, nonce, attachment, visibility, and
  disabled state.
- `WebViewFlutterEngine`: the `webview_flutter` controller wrapper. No
  JavaScript channel and no `addJavascriptInterface`.
- Tests: registry validation, script contents (including a text-injection case),
  and capture/action behaviour against a fake engine.

### Changed

- SPA History navigation advances the snapshot epoch from the page's
  `location.href` (the controller URL can lag a `pushState`), and the action
  script refuses when `store.href` no longer matches `location.href`.

### Fixed

- Android's `runJavaScriptReturningResult` returns the raw
  `evaluateJavascript` text, so a script returning `JSON.stringify(...)`
  arrived double-encoded and every capture failed as `script_failed`. The
  adapter now unwraps string results until a map appears; found on a real
  device, covered by a unit test.
- The whitespace normalizer in the generated page script emitted `/s+/g`
  instead of `/\s+/g` (Dart collapsed the escape), which mangled labels such
  as "Search orders". The script now emits `\s` and a script test pins it.

### Verified

- Release APK on Huawei PTP-AN10 / Android 17 (2026-11-04): the demo's local H5
  page was listed, read with the PIN masked, filled, clicked, and re-read; a
  replayed snapshot was refused; capture on the WebView route was blocked.
