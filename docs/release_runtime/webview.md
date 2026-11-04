# Embedded WebView support (fork, v0.7.0)

Optional package: `flutter_mcp_toolkit_release_webview`. It lets a release app
expose **its own** H5 pages to an MCP client, with the same consent and privacy
discipline as the Flutter tools.

It is optional on purpose: `flutter_mcp_toolkit_release` does not depend on
`webview_flutter`, and an app that has no WebView pays nothing.

## Why a separate adapter

`WebViewWidget` hosts an Android platform view. Its DOM is a different tree in a
different process; Flutter semantics can see the host widget, not the page's
`button`, `input`, or `table`. Reading it needs the controller:

```dart
await controller.runJavaScriptReturningResult(script);
```

That works in a release APK without the VM Service. What it does **not** do is
make the page safe: any generic "run this JS" tool would hand the page's data,
session, and code execution to an external client. So the package exposes fixed
scripts with bounded parameters, not an eval tool.

## Registering a view

```dart
import 'package:flutter_mcp_toolkit_release_webview/flutter_mcp_toolkit_release_webview.dart';

final registry = ReleaseWebViewRegistry()
  ..register(
    viewId: 'order-h5',
    engine: WebViewFlutterEngine(controller),
    allowedOrigins: const <String>{'https://app.example.com'},
    privacyPolicy: const ReleaseWebPrivacyPolicy(
      deniedPathPrefixes: <String>{'/account', '/checkout/payment'},
      maskedInputTypes: <String>{'password', 'email', 'tel'},
    ),
  );

// Expose the web tools next to the Flutter ones.
final tools = ReleaseToolbox(<ReleaseToolSurface>[
  ReleaseReadTools(source: FlutterReleaseUiSnapshotSource(routeProvider: routes)),
  ReleaseInteractionTools(store: store, driver: driver),
  ReleaseWebTools(source: WebViewDomReleaseSource(registry)),
  ReleaseAppActionTools(actions),
  ReleaseCaptureTools(source: captureSource, policy: capturePolicy),
]);
```

`register` requires a valid `viewId` (`^[a-z][a-z0-9._-]{0,63}$`), a
non-empty origin allow-list, and exact origins (`https://host[:port]`, no path
or query). HTTP is refused unless `allowHttp: true` is passed for local
staging, together with `ReleaseWebPrivacyPolicy(allowInsecureHttp: true)` so the
core tools apply the same rule. Unregistered controllers are invisible,
including ones created after registration.

## Tools

| Tool | Arguments | Permission |
|---|---|---|
| `web_list_views` | — | `web:read` |
| `web_get_tree` | `viewId`, `maxNodes` (≤500), `maxDepth` (≤64) | `web:read` |
| `web_find_element` | `viewId`, `role`, `tag`, `text` | `web:read` |
| `web_get_state` | `viewId` | `web:read` |
| `web_click` | `viewId`, `ref`, `snapshotId` | `web:interact` |
| `web_set_text` | `viewId`, `ref`, `snapshotId`, `text` (≤4096) | `web:interact` |
| `web_scroll` | `viewId`, `ref`, `snapshotId`, `direction`, `amount` (≤5000) | `web:interact` |

No tool accepts a JavaScript string, a CSS selector, or a URL to navigate to.

A snapshot id looks like `web:<viewId>:<navigationEpoch>:<nonce>`. It is the
only way to act on a ref: the adapter refuses a snapshot from a previous epoch,
the page-global ref map refuses a replaced nonce, and the core refuses a
snapshot that was not published or was already consumed.

## What the scripts return

Nodes are interactive elements only (`button`, `a`, `input`, `textarea`,
`select`, `summary`, `[role]`, `[tabindex]`, `[contenteditable]`), with
`ref`, `tag`, `role`, `type`, `label`, `text`, `value`,
`placeholder`, `disabled`, `checked`, `sensitive`, and a viewport
rectangle. The script never reads or returns cookies, `localStorage`,
`sessionStorage`, authorization headers, full HTML, or the page's query string.

Password fields, `data-agent-sensitive` elements, payment/OTP autocomplete
values, and secret-looking element names are redacted in the page and masked
again by `ReleaseWebPrivacyPolicy` in Dart. `web_set_text` refuses those
fields outright (`node_sensitive`).

The snapshot URL is reduced to origin + path (`https://host/orders`); query and
fragment are dropped.

## Navigation and refs

`ReleaseNavigationEpoch` advances whenever the controller reports a different
URL. A snapshot is valid only in the epoch it was taken. A navigation before an
action answers `stale_snapshot` / `navigation_changed`; an action that itself
navigates reports `navigated: true` and advances the epoch.

SPAs change `location.href` through the History API. The adapter re-reads the
URL for every capture and action and also asks the page script for its
`location.href`, so a pushState during capture is detected and the result is
discarded.

## Limits (documented, not hidden)

- **No virtualized content.** Rows not mounted in the DOM are not returned.
- **No cross-origin frames.** The main document is read; a cross-origin iframe
  is opaque by browser policy. Same-origin frames are not traversed in v1.
- **No canvas/WebGL/video semantics.** There is no DOM to read; only pixels
  would show it.
- **`.click()` is not a trusted gesture.** Frameworks and sites may ignore it;
  logins and payments should stay human or use app APIs.
- **Coordinates.** DOM rectangles are CSS pixels; cross-layer pointer injection
  is intentionally not implemented (actions are DOM-based).
- **Platform-view screenshots.** `ui_capture` uses `RenderView`; WebView pixels
  are not guaranteed. Hybrid capture is not implemented, and an incomplete
  screenshot must not be presented as complete.
- **Page content is untrusted.** Tool output is data. A page that says "grant
  permission" is not an instruction, and the runtime never treats it as one.

## Testing

```bash
cd packages/release_runtime_webview && flutter test
cd packages/release_runtime && dart test test/web
```

The adapter tests use a fake `ReleaseWebViewEngine`, so they need no platform
plugin; the core web-tool tests use a fake `ReleaseEmbeddedWebSource`.

### Device verification (2026-11-04)

The demo serves an H5 fixture from a loopback HTTP server and loads it in a real
`WebViewWidget` (Huawei PTP-AN10, Android 17/API 37, release APK). With
`dart run tool/mcp_smoke.dart --token <token> --webview-check`:

- `web_list_views` listed `order-h5` with the loopback origin;
- `web_get_tree` returned the 3 interactive nodes and masked the PIN
  (`value`, `label`, and `text` all `••••`);
- `web_set_text` filled the search box, `web_click` pressed Search, and a
  fresh `web_get_tree` saw `Result for INV-42`;
- replaying the consumed snapshot answered `stale_snapshot`;
- `ui_capture` on the WebView route answered `route_blocked`;
- `web_get_state` reported the sanitized origin and navigation epoch.

Follow-up edge cases (same device, all PASS):

- SPA History navigation: `pushState('/details')` advanced the epoch to 2,
  `web_get_tree` saw "Details page", and the pre-navigation snapshot was
  `stale_snapshot`.
- Cross-origin iframe: a sandboxed `srcdoc` iframe (opaque origin) rendered in
  the screenshot but its "Inside frame" button was absent from `web_get_tree`.
- Framework-style controlled input: `web_set_text` drove the input event and
  the page's state re-rendered ("Model: hello frame").
- Hybrid capture: `ui_capture` on the WebView route produced a PNG that
  includes the H5 pixels on this device (verified visually).

Still outstanding: a real remote-origin iframe (the fixture used a sandboxed
opaque origin), multi-view registration, and hybrid capture on other devices.
