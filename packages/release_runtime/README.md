# flutter_mcp_toolkit_release

Opt-in MCP runtime for **shipped** Flutter apps.

`mcp_toolkit` gives an agent a window into a *debug* build over the Dart VM
Service. This package is the other half of the story: a guarded MCP surface that
lives inside a *release* build — loopback HTTP, bearer token, no VM Service, no
service extensions, no Dart eval, no hot reload.

> **Status: PR-01 … PR-06 of the fork plan — verified on a release APK.** Configuration, lifecycle, consent,
> bearer authentication, the Streamable HTTP endpoint, and three read-only UI
> tools are implemented and tested. The Flutter side (the actual semantics walk)
> lives in [`flutter_mcp_toolkit_release_flutter`](../release_runtime_flutter).
> See [android-deploy.md](../../docs/release_runtime/android-deploy.md) for what the device run proved.

## Why a separate package

| | `mcp_toolkit` (debug) | `flutter_mcp_toolkit_release` (this) |
|---|---|---|
| Transport | VM Service (DDS) | Streamable HTTP on loopback |
| Runs in | debug/profile only | release builds |
| Tools | `fmt_*` debug surface | allow-listed UI + app actions only |
| Default | on with the debug binding | **off**, loopback-only, read-only |
| Extras | eval, hot reload, extensions | none, by construction |

## Wiring it into an app

```dart
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';
import 'package:flutter_mcp_toolkit_release_flutter/flutter_mcp_toolkit_release_flutter.dart';

final runtime = ReleaseMcpRuntime.http(
  config: const ReleaseMcpConfig(port: 8765, endpoint: '/mcp'),
  tools: ReleaseReadTools(
    source: FlutterReleaseUiSnapshotSource(
      routeProvider: CallbackReleaseRouteProvider(() async => myRouter.path),
    ),
  ),
);

// Nothing is bound yet. Show runtime.accessToken as the pairing code when the
// user enables "allow local AI access", then:
await runtime.start(
  authorization: ReleaseStartAuthorization.readOnly(reason: 'user enabled'),
);
```

A client then talks MCP to `http://127.0.0.1:8765/mcp` with
`Authorization: Bearer <token>`, and `tools/list` shows `ui_get_tree`,
`ui_get_current_page`, `ui_find_element`.

## Tools (v1)

| Tool | Permission | What it returns |
|---|---|---|
| `ui_get_tree` | `ui:read` | Flat semantic node list with refs, budgets (`maxNodes`/`maxDepth`), `truncated` flag |
| `ui_get_current_page` | `ui:read` | Route name, interaction surface, node count |
| `ui_find_element` | `ui:read` | Exactly one match by identifier/label/role, or a refusal |
| `ui_click` | `ui:interact` | Taps one ref; requires the `snapshotId` that issued it |
| `ui_set_text` | `ui:interact` | Types into a field; refuses sensitive (password-like) nodes |
| `ui_scroll` | `ui:interact` | Scrolls a list by direction and amount |
| `app_invoke_action` | `app:<name>` | Runs a business action the app registered |
| `ui_capture` | `ui:capture` | PNG screenshot, refused on policy-blocked routes |

Write tools need `ui:interact` **and** the `snapshotId`, are serialized, and
consume their snapshot: acting twice on one snapshot yields one action and one
`stale_snapshot`.

Refusals are `success: false` payloads with stable codes
(`invalid_argument`, `element_not_found`, `ambiguous_match`, `permission_denied`,
…), not protocol errors, so a client can correct itself.

## Guarantees this package enforces

- **No side effects on construction.** Nothing binds, listens, or starts;
  `enabledOnStartup` is a hint for the host app.
- **Loopback by default.** A non-loopback `host` fails validation unless
  `allowNonLoopbackBinding` is set; `host:port` strings are rejected.
- **Authentication is mandatory.** `Authorization: Bearer <token>` on every
  request; the token comes from `Random.secure()`, is redacted in
  `toString()`, and never appears in status JSON or a URL.
- **Origin is validated.** SDK loopback allow-list, `allowAnyOrigin: false`.
- **No wildcard CORS, no silent rebinding** (`fallbackPorts: const []`).
- **Read-only by default.** `ui:interact`, `ui:capture`, and `app:<name>`
  require explicit `ReleaseStartAuthorization` grants.
- **Every tool call is permission-checked** by the runtime before the handler
  runs; a handler that throws becomes `unknown_error` plus an exception type.
- **No node text without redaction.** Sensitive nodes (obscured semantics) are
  masked by `RedactingPrivacyFilter`; long text is truncated.
- **Stable error codes** with fixed, non-sensitive messages.

## Verifying it works

```bash
dart test packages/release_runtime                    # 135 tests
flutter test packages/release_runtime_flutter         # 12 widget tests
dart run packages/release_runtime/example/release_http_smoke.dart
```

## Platform note

The HTTP transport uses `dart:io`, so this package targets native targets
(Android first). It is not a web package.

## License

MIT, same as the repository.