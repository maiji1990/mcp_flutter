# Android deployment

How to build, install, and verify the release runtime on a device, and what has
actually been verified.

## 1. Manifest permission

The runtime binds a loopback socket, which needs `INTERNET` in the **release**
manifest — the debug manifest's permission does not carry over:

```xml
<uses-permission android:name="android.permission.INTERNET" />
```

No cleartext exception is needed: the app only *listens*, it never makes an HTTP
request to itself. The client is the computer.

## 2. Build and install

```bash
cd showcase/flutter_release_demo
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell am start -n com.example.flutter_release_demo/.MainActivity
```

### Enabling without a human at the phone

For scripted verification, the demo screen's controls are addressable through
`uiautomator`:

```bash
adb shell uiautomator dump /sdcard/ui.xml && adb pull /sdcard/ui.xml
# the switch is the node whose content-desc contains "Allow local AI access";
# "Grant all" is a Button node; tap each with its reported bounds
adb shell input tap <x> <y>
```

Huawei devices also ask for confirmation on `adb install` ("unknown source"
warning); the dialog's **继续 / Continue** button must be tapped.

## 3. Enable access in the app

1. Toggle **Allow local AI access**. The runtime starts *read-only* on
   `127.0.0.1:8765/mcp`; nothing listens before this.
2. Tap **Grant all** to add `ui:interact`, `ui:capture`, `web:read`,
   `web:interact`, and `app:demo.increment` for the session. Nothing is granted
   implicitly.
3. Copy the **pairing token** shown under the switch. It is a per-launch secret.
4. Optionally open **Open WebView demo**: the app starts a loopback HTTP server
   for a fixture H5 page, loads it in a real `WebViewWidget`, and registers it
   as `order-h5` (origin allow-list = that loopback origin). The page has a
   search box, a Search button, a results list, and a password field.

## 4. Reach it from the computer

```bash
adb forward tcp:8765 tcp:8765
cd showcase/flutter_release_demo
dart run tool/mcp_smoke.dart --token <token> --webview-check --wallet-check
```

The smoke tool performs, against the real endpoint: `initialize`,
`tools/list` (15 tools), `ui_get_current_page`, `ui_get_tree`, `ui_click`,
a read-back that the counter changed, `ui_find_element`, `ui_set_text`, a value
read-back, `ui_scroll`, an invalid `app_invoke_action` (refused) and a valid
one, `ui_capture` (PNG decode), a click without `snapshotId` (refused), the
WebView flow (list, DOM read with the PIN masked, set text, click, result,
snapshot replay refused, capture on `/web-demo` refused), and the wallet checks
(read `route_denied`, no card number, capture `route_blocked`, no bytes). It
exits non-zero if any step fails.

## 5. What has been verified

### v0.7.0 re-run — 2026-11-04

Release APK (18.4 MB) built with Flutter 3.47.9 / Dart 3.13.7, installed on a
**Huawei PTP-AN10 (PTP_AN10), Android 17 (API 37), arm64**. All smoke steps
passed with `--webview-check --wallet-check`:

| Item | Evidence |
|---|---|
| Protocol | `initialize` reports `flutter_mcp_toolkit_release 0.7.0`; `tools/list` returns 15 tools (8 Flutter + 7 `web_*`) |
| UI flow | `ui_get_tree` (30 nodes, `routeName: /`), `ui_click` (counter changed), `ui_set_text` (read back), `ui_scroll`, `ui_capture` (512x1120 PNG, ~70 KB) |
| Action schema | `app_invoke_action` with `{unexpected: true}` → `invalid_argument`; the valid call ran (`{count: 4}`) |
| Wallet privacy | `ui_get_tree` on `/wallet` → `route_denied`, payload contains no `4111`; `ui_capture` → `route_blocked`, no `bytesBase64` |
| WebView list/read | `web_list_views` shows `order-h5` with the loopback origin; `web_get_tree` returns 3 nodes, PIN `value/label/text` masked |
| WebView actions | `web_set_text` filled the search box, `web_click` pressed Search, a fresh `web_get_tree` saw `Result for INV-42` |
| WebView discipline | replay of the consumed snapshot → `stale_snapshot`; `ui_capture` on `/web-demo` → `route_blocked`; `web_get_state` reports origin and epoch |
| Snapshot discipline | click without `snapshotId` refused; ambiguous role query → `ambiguous_match` |
| WebView edge cases | SPA `pushState` → epoch 2 and the old snapshot `stale_snapshot`; sandboxed iframe button absent from `web_get_tree` but visible in the PNG; controlled input re-rendered (`Model: hello frame`) |
| Hybrid capture | `ui_capture` on `/web-demo` → 640x1400 PNG containing the H5 pixels (visual check) |
| Lifecycle | HOME/lock stop the endpoint (`paused (app in background)`); landscape↔portrait stays healthy; re-enable rotates the token and the old one is 401 |
| Multi-client | two sessions read and acted concurrently under one grant (AUTH-02 gap recorded) |
| Rate limit / audit | 130 calls → 115 OK + 15 `rate_limited`; logcat audit records carry tool/permission/decision/epoch, no values |
| Process death | force-stop → endpoint unreachable; relaunch → `Status: off` |
| Split / freeform | windowing transition paused the activity and stopped the endpoint (foreground-only by design) |

Two defects were found only on hardware and fixed before this table was
recorded: Android returns `evaluateJavascript` string results double-encoded,
and a Dart `\s` escape reached the page script as `s` (mangling labels). Both
now have regression tests.

Full transcripts (token redacted):
[`evidence/2026-11-04-device-smoke.txt`](evidence/2026-11-04-device-smoke.txt),
[`evidence/2026-11-04-device-extended.txt`](evidence/2026-11-04-device-extended.txt).

### v0.6.0 record — 2026-11-04

This earlier run predates the v0.7.0 controls; it is kept as history.

| Item | Evidence |
|---|---|
| Release APK builds | `flutter build apk --release --target-platform android-arm64` → 16.7 MB |
| Nothing answers before enabling | request to `http://127.0.0.1:8765/mcp` fails while the toggle is off |
| Auth is enforced | the same request with no token answers **401** |
| Protocol works on device | `initialize` reports `flutter_mcp_toolkit_release 0.6.0` (the run predates v0.7.0); `tools/list` returns the eight tools |
| Observation works | `ui_get_tree` → 29 nodes, `routeName: /`, `interactionSurface: flutter_widgets` |
| Interaction works | `ui_click` dispatched via `semantic_action` and the counter label changed; `ui_set_text` via `editable_state` with `verified: true` and the value read back; `ui_scroll` via `semantic_scroll_to_offset` |
| Business action works | `app_invoke_action` returned `{count: 6}` |
| Capture works | `ui_capture` at `scale: 0.4` → 512x1120 PNG, 57 KB, valid signature |
| Capture policy holds | `ui_capture` on `/wallet` → `route_blocked` (v0.7.0 additionally refuses every route not listed in `allowedRoutes`, and reads of `/wallet` now answer `route_denied`) |
| Snapshot discipline holds | click without `snapshotId` refused; ambiguous role query → `ambiguous_match` |

Defect found by this run: sessions were capped by `maxConcurrentRequests` (4), so
the fifth client run was refused with "Too many sessions". `maxSessions`
(default 32) and `sessionIdleTimeout` (10 min) now own that budget; a regression
test opens six sessions.

Not covered by the v0.7.0 run: lock screen, background/process death, rotation,
multi-window, multiple clients, SPA History navigation, cross-origin iframes,
framework-controlled inputs, hybrid (platform-view) screenshots, and any API
level below 37. They are listed in [security.md](security.md).

## 6. Troubleshooting

- **`adb forward` says "cannot bind listener"** — port 8765 is already in use on
  the computer (another forward, or a local server).
- **Connection refused** — the toggle is off, or the app was killed; the runtime
  lives only while the app is in the foreground.
- **401 on every request** — the token rotates per launch; re-read it from the
  app after restarting.
- **Empty `ui_get_tree`** — the app is on a screen with no semantics yet (a
  frame has not been laid out) or is a raw canvas UI; take a screenshot instead.