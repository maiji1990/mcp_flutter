# flutter_mcp_toolkit_release

Opt-in MCP runtime for **shipped** Flutter apps.

`mcp_toolkit` gives an agent a window into a *debug* build over the Dart VM
Service. This package is the other half of the story: a guarded MCP surface that
lives inside a *release* build — no VM Service, no service extensions, no Dart
eval, no hot reload, nothing that a debug build would have offered anyway.

> **Status: PR-01 of the fork plan.** This PR lands configuration, the lifecycle
> state machine, consent handling, the transport seam, and unit tests. There is
> deliberately **no network code, no MCP SDK dependency, and no tool catalog**
> yet — those land in PR-02 and later. See
> [`docs/release_runtime/README.md`](../../docs/release_runtime/README.md) for the
> full roadmap.

## Why a separate package

| | `mcp_toolkit` (debug) | `flutter_mcp_toolkit_release` (this) |
|---|---|---|
| Transport | VM Service (DDS) | pluggable `ReleaseRuntimeTransport` |
| Runs in | debug/profile only | release builds |
| Tools | `fmt_*` debug surface | allow-listed UI + app actions only |
| Default | on with the debug binding | **off**, loopback-only, read-only |
| Extras | eval, hot reload, extensions | none, by construction |

Keeping them apart means a release build cannot accidentally inherit a debug
capability, and the debug path keeps its current behaviour untouched.

## Quick start

```dart
import 'package:flutter_mcp_toolkit_release/flutter_mcp_toolkit_release.dart';

final runtime = ReleaseMcpRuntime(
  config: const ReleaseMcpConfig(
    host: '127.0.0.1',
    port: 8765,
    endpoint: '/mcp',
    enabledOnStartup: false,
    readOnlyByDefault: true,
  ),
);

// Nothing is bound yet: constructing a runtime has no side effects.

// Only when the user flips "allow local AI access" in your UI:
await runtime.start(
  authorization: ReleaseStartAuthorization.readOnly(reason: 'user enabled'),
);

// Later:
await runtime.stop();
await runtime.dispose();
```

`start`, `stop`, and `dispose` are idempotent and serialized; concurrent calls
never interleave a transport handoff.

## Guarantees this PR already enforces

- **No side effects on construction.** Import the package, construct a runtime,
  and nothing binds, listens, or starts. `enabledOnStartup` is a hint for the
  host app, not an auto-start.
- **Loopback by default.** A non-loopback `host` fails validation unless
  `allowNonLoopbackBinding` is explicitly set. `host:port` strings and URL
  spellings are rejected rather than silently re-bound.
- **Read-only by default.** `ui:read` is granted by starting. `ui:interact`,
  `ui:capture`, and every `app:<name>` permission require an explicit
  `ReleaseStartAuthorization`.
- **No silent downgrade.** When `readOnlyByDefault` is false, starting without
  consent fails with `authorization_missing` instead of quietly serving
  read-only.
- **Stable error codes.** Every failure is a `ReleaseMcpException` carrying a
  code from `ReleaseMcpErrorCode` plus a non-sensitive message; details carry
  field names and error *types*, never request bodies, tokens, or node text.

## Public API

See [`docs/release_runtime/api.md`](../../docs/release_runtime/api.md).

## Tests

```bash
dart test packages/release_runtime
```

The package is a member of the repo's pub workspace, so a full
`flutter pub get` at the repo root resolves it alongside the other packages.

## License

MIT, same as the repository.
