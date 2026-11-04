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
2. Tap **Grant all** to add `ui:interact`, `ui:capture`, and
   `app:demo.increment` for the session. Nothing is granted implicitly.
3. Copy the **pairing token** shown under the switch. It is a per-launch secret.

## 4. Reach it from the computer

```bash
adb forward tcp:8765 tcp:8765
dart run showcase/flutter_release_demo/tool/mcp_smoke.dart --token <token>
```

The smoke tool performs, against the real endpoint: `initialize`, `tools/list`
(8 tools), `ui_get_current_page`, `ui_get_tree`, `ui_click`, a read-back that
the counter changed, `ui_find_element`, `ui_set_text`, a value read-back,
`ui_scroll`, `app_invoke_action`, `ui_capture` (PNG decode), and a refusal for
a click without `snapshotId`. It exits non-zero if any step fails.

## 5. What has been verified

Measured on **2026-11-04**, release APK built with Flutter 3.47.9 / Dart 3.13.7,
installed on a **Huawei PTP-AN10, Android 17 (API 37), arm64**.

| Item | Evidence |
|---|---|
| Release APK builds | `flutter build apk --release --target-platform android-arm64` → 16.7 MB |
| Nothing answers before enabling | request to `http://127.0.0.1:8765/mcp` fails while the toggle is off |
| Auth is enforced | the same request with no token answers **401** |
| Protocol works on device | `initialize` reports `flutter_mcp_toolkit_release 0.6.0`; `tools/list` returns the eight tools |
| Observation works | `ui_get_tree` → 29 nodes, `routeName: /`, `interactionSurface: flutter_widgets` |
| Interaction works | `ui_click` dispatched via `semantic_action` and the counter label changed; `ui_set_text` via `editable_state` with `verified: true` and the value read back; `ui_scroll` via `semantic_scroll_to_offset` |
| Business action works | `app_invoke_action` returned `{count: 6}` |
| Capture works | `ui_capture` at `scale: 0.4` → 512x1120 PNG, 57 KB, valid signature |
| Capture policy holds | `ui_capture` on `/wallet` → `route_blocked` |
| Snapshot discipline holds | click without `snapshotId` refused; ambiguous role query → `ambiguous_match` |

Defect found by this run: sessions were capped by `maxConcurrentRequests` (4), so
the fifth client run was refused with "Too many sessions". `maxSessions`
(default 32) and `sessionIdleTimeout` (10 min) now own that budget; a regression
test opens six sessions.

Not covered: lock screen, background/process death, rotation, multi-window,
and any API level below 37. They are out of scope for V1 or untested, and are
listed in [security.md](security.md).

## 6. Troubleshooting

- **`adb forward` says "cannot bind listener"** — port 8765 is already in use on
  the computer (another forward, or a local server).
- **Connection refused** — the toggle is off, or the app was killed; the runtime
  lives only while the app is in the foreground.
- **401 on every request** — the token rotates per launch; re-read it from the
  app after restarting.
- **Empty `ui_get_tree`** — the app is on a screen with no semantics yet (a
  frame has not been laid out) or is a raw canvas UI; take a screenshot instead.