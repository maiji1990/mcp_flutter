# flutter_release_demo

The fixture that proves the release runtime on a device: a small app whose UI an
MCP client can observe and drive over loopback HTTP, with the same consent
surface a real app would have.

```bash
flutter build apk --release --target-platform android-arm64
adb install -r build/app/outputs/flutter-apk/app-release.apk
# enable "Allow local AI access", tap "Grant all", then:
adb forward tcp:8765 tcp:8765
dart run tool/mcp_smoke.dart --token <pairing token> --wallet-check
```

What the screen offers:

| Widget | Proves |
|---|---|
| Consent switch | nothing listens until the user enables access; the token is shown only then |
| Grant buttons | `ui:interact`, `ui:capture`, and `app:demo.increment` are separate consents |
| Counter + Increment | `ui_click` changes app state, readable in the next tree |
| Name field | `ui_set_text` writes and the value reads back |
| 40-row list | `ui_scroll` |
| "Open secret screen" (`/wallet`) | the capture policy refuses pixels on a blocked route |

`tool/mcp_smoke.dart` runs the whole list against the device and exits non-zero
on any failure; `tool/mcp_probe.dart` prints the nodes the device reports, which
is what to reach for when a label is not where you expected.

See [`docs/release_runtime/android-deploy.md`](../../docs/release_runtime/android-deploy.md)
for the verified matrix and the caveats.
