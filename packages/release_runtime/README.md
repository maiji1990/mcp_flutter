# flutter_mcp_toolkit_release

Opt-in MCP runtime for **shipped** Flutter apps.

`mcp_toolkit` gives an agent a window into a *debug* build over the Dart VM
Service. This package is the other half of the story: a guarded MCP surface that
lives inside a *release* build — loopback HTTP, bearer token, no VM Service, no
service extensions, no Dart eval, no hot reload.

> **Status: PR-01 + PR-02 of the fork plan.** Configuration, lifecycle, consent,
> bearer authentication, and a Streamable HTTP endpoint are implemented and
> tested. The tool catalog (semantic snapshot, interactions, app actions,
> capture) is PR-03+, so `tools/list` is currently empty by design. See
> [`docs/release_runtime/README.md`](../../docs/release_runtime/README.md).

## Why a separate package

| | `mcp_toolkit` (debug) | `flutter_mcp_toolkit_release` (this) |
|---|---|---|
| Transport | VM Service (DDS) | Streamable HTTP on loopback |
| Runs in | debug/profile only | release builds |
| Tools | `fmt_*` debug surface | allow-listed UI + app actions only |
| Default | on with the debug binding | **off**, loopback-only, read-only |
| Extras | eval, hot reload, extensions | none, by construction |

Keeping them apart means a release build cannot accidentally inherit a debug
capability, and the debug path keeps its current behaviour untouched.

## Quick start

```dart
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

final runtime = ReleaseMcpRuntime.http(
  config: const ReleaseMcpConfig(
    host: '127.0.0.1',
    port: 8765,
    endpoint: '/mcp',
    enabledOnStartup: false,
    readOnlyByDefault: true,
  ),
);

// Nothing is bound yet: constructing a runtime has no side effects.
// Show runtime.accessToken to the user as the pairing code when they enable
// "allow local AI access".

await runtime.start(
  authorization: ReleaseStartAuthorization.readOnly(reason: 'user enabled'),
);
// -> http://127.0.0.1:8765/mcp, Authorization: Bearer <runtime.accessToken.value>

await runtime.stop();
await runtime.dispose();
```

`start`, `stop`, and `dispose` are idempotent and serialized; concurrent calls
never interleave a transport handoff.

## Guarantees this package enforces

- **No side effects on construction.** Import the package, construct a runtime,
  and nothing binds, listens, or starts. `enabledOnStartup` is a hint for the
  host app, not an auto-start.
- **Loopback by default.** A non-loopback `host` fails validation unless
  `allowNonLoopbackBinding` is explicitly set. `host:port` strings and URL
  spellings are rejected rather than silently re-bound.
- **Authentication is mandatory.** Every request needs
  `Authorization: Bearer <token>`; the SDK compares it in constant time and
  answers 401 before dispatch. The token comes from `Random.secure()`, is
  redacted in `toString()`, and never appears in status JSON or a URL.
- **Origin is validated.** The SDK's loopback-only Origin allow-list stays on
  (`allowAnyOrigin: false`), so a remote page cannot drive the app through DNS
  rebinding; a foreign `Origin` gets 403.
- **No wildcard CORS.** `Access-Control-Allow-Origin` names the loopback origin.
- **No silent rebinding.** `fallbackPorts` is empty: a taken port is
  `transport_start_failed`, not `port + 1`.
- **Read-only by default.** `ui:read` is granted by starting. `ui:interact`,
  `ui:capture`, and every `app:<name>` permission require an explicit
  `ReleaseStartAuthorization`.
- **No silent downgrade.** When `readOnlyByDefault` is false, starting without
  consent fails with `authorization_missing` instead of quietly serving
  read-only.
- **Stable error codes.** Every failure is a `ReleaseMcpException` carrying a
  code from `ReleaseMcpErrorCode` plus a fixed, non-sensitive message.

## Verifying it works

```bash
dart test packages/release_runtime
dart run packages/release_runtime/example/release_http_smoke.dart
```

The smoke run prints a real handshake: `401` without a token, `initialize` with
a session id, `tools/list` → `{"tools":[]}`, then the port is released on stop.

The MCP protocol itself (initialize, sessions, protocol-version negotiation,
batching) is implemented by the published `mcp_server` package, not by this
package.

## Public API

See [`docs/release_runtime/api.md`](../../docs/release_runtime/api.md).

## Platform note

The HTTP transport uses `dart:io`, so this package targets native targets
(Android first). It is not a web package.

## License

MIT, same as the repository.
