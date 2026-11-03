# `flutter_mcp_toolkit_release` API (PR-01 + PR-02)

Everything below is implemented and covered by `dart test`. The MCP tools
themselves are PR-03+, so `tools/list` is currently empty.

## `ReleaseMcpRuntime`

```dart
ReleaseMcpRuntime({
  ReleaseMcpConfig config = const ReleaseMcpConfig(),
  ReleaseRuntimeTransport? transport,
  ReleaseAccessToken? accessToken,
})

factory ReleaseMcpRuntime.http({
  ReleaseMcpConfig config = const ReleaseMcpConfig(),
  ReleaseAccessToken? accessToken,
})
```

Construction binds nothing, starts nothing, and reads no platform state.
`ReleaseMcpRuntime.http` is the release-ready shape: it wires
`HttpReleaseRuntimeTransport` (Streamable HTTP over loopback).

| Member | Contract |
|---|---|
| `config` | Public final field: the configuration the runtime was built with. |
| `state` | Current `ReleaseRuntimeState`. |
| `stateChanges` | Broadcast `Stream<ReleaseRuntimeState>`, emitted after commit. |
| `status` | Read-only `ReleaseRuntimeStatus` snapshot. |
| `statusChanges` | Broadcast `Stream<ReleaseRuntimeStatus>`. |
| `accessToken` | The bearer secret; `toString()` is redacted. |
| `isDisposed` | True after `dispose()`. |
| `start({authorization})` | `Future<ReleaseRuntimeStatus>`. Idempotent. |
| `stop()` | `Future<ReleaseRuntimeStatus>`. Idempotent; safe from `error`. |
| `grantPermissions(ids)` | Adds consent while running. |
| `revokePermissions(ids)` | Withdraws consent while running; `ui:read` stays. |
| `rotateAccessToken()` | New token; only while `disabled`. |
| `dispose()` | Idempotent teardown; never throws. |

### `start` semantics

1. Disposed runtime → `runtime_disposed`.
2. Already `running` → returns the current status, transport untouched.
3. Invalid config → `invalid_config` with the failed `problems`; state stays
   `disabled`, transport untouched.
4. `readOnlyByDefault: false` and no `authorization` → `authorization_missing`.
5. Effective permissions are `{ui:read} ∪ authorization.grantedPermissions`.
6. The transport is handed host/port/endpoint/timeouts **and the bearer token**.
7. Transport throws → state `error`, code `transport_start_failed`, session
   cleared, `ReleaseMcpException` rethrown.

Concurrent `start` / `stop` calls are queued: five simultaneous `start()` calls
produce exactly one transport start.

### `stop` / `dispose` / rotation

`stop` is a no-op while `disabled`; from `error` it re-enters `stopping` and
lands in `disabled` with the error code cleared, releasing the port.
`dispose` stops the transport, clears the session, closes both streams, and
never throws.

Rotation is `stop()` → `rotateAccessToken()` → `start()`. While running it
throws `invalid_state_transition` (`reason: rotation_requires_stopped`): the
transport captured the old token when it bound, and rebinding under a live
client would either keep the old secret alive or break the endpoint.

## `ReleaseAccessToken`

256 bits from `Random.secure()`, base64url without padding (43 chars).

| Member | Contract |
|---|---|
| `value` | The secret. Never log it, never put it in a URL. |
| `issuedAt` | UTC mint time, for the audit trail. |
| `authorizationHeader` | `Bearer <value>`. |
| `matches(candidate)` | Constant-time comparison. |
| `toString()` | `ReleaseAccessToken(issuedAt: …, value: <redacted>)`. |

## `ReleaseMcpConfig`

| Field | Default | Rule |
|---|---|---|
| `host` | `127.0.0.1` | Loopback only (`127.0.0.1`, `::1`, `localhost`) unless `allowNonLoopbackBinding`. No schemes, paths, or `host:port`. |
| `port` | `8765` | `0..65535`; `0` requests an ephemeral port. |
| `endpoint` | `/mcp` | Absolute path, no query or fragment, `2..128` chars. |
| `enabledOnStartup` | `false` | Hint for the host app only; never auto-starts. |
| `readOnlyByDefault` | `true` | `false` makes a missing authorization an error. |
| `allowNonLoopbackBinding` | `false` | Explicit opt-in for LAN/public binds (not supported in V1). |
| `maxRequestBytes` | `1 MiB` | `1 KiB .. 8 MiB`; becomes the transport's body ceiling. |
| `requestTimeout` | `30 s` | `> 0` and `<= 5 min`; enforced by the transport. |
| `maxConcurrentRequests` | `4` | `1..64`; becomes the SDK's max concurrent sessions. |

`validate()` returns every violated rule as `ReleaseConfigProblem(field, code)`
in a stable order; `isValid` is the boolean shortcut. `toJson()` is
redaction-safe (no token, no secret).

## `ReleaseRuntimeState`

`disabled`, `starting`, `running`, `stopping`, `error` — each with a stable
`wireName`, plus `isTransitional` and `isServing`.

```
disabled → starting → running → stopping → disabled
                ↓        ↓         ↓
              error ←────┴─────────┘      (error → disabled | starting | stopping)
```

Illegal transitions throw `StateError`: they are programming errors, not
recoverable conditions.

## Errors

`ReleaseMcpException(code, {problems, details})`, `toJson()` yields `code`,
`message`, `category`, `retryable`, `httpLikeStatus`, `problems`, `details`.

The message is fixed per code: callers cannot supply prose, so a failure can
never echo request data or a token. Structured, non-sensitive breadcrumbs go in
`details` (field names, error *types*) and `problems`.

| Code | Category | Retryable | HTTP-like |
|---|---|---|---|
| `invalid_config` | config | no | 400 |
| `invalid_permission_id` | permission | no | 400 |
| `authorization_missing` | permission | no | 403 |
| `permission_denied` | permission | no | 403 |
| `invalid_state_transition` | state | no | 409 |
| `transport_not_configured` | transport | no | 501 |
| `transport_start_failed` | transport | yes | 503 |
| `transport_stop_failed` | transport | yes | 503 |
| `runtime_not_running` | state | no | 409 |
| `runtime_disposed` | state | no | 409 |
| `unknown_error` | internal | no | 500 |

Wire-level refusals from the transport are HTTP statuses, not these codes:
401 (missing/wrong bearer), 403 (foreign `Origin`), 405 (GET), 413 (body over
the ceiling).

## Permissions

`ui:read` · `ui:interact` · `ui:capture` · `app:<name>` where `<name>` matches
`^[a-z][a-z0-9._-]{0,63}$`.

`ReleasePermissionSet` is an immutable set with `union`, `difference`,
`contains`, `isReadOnly`, and a sorted `toWireList()` for stable JSON.
`ReleaseStartAuthorization` carries the grants (plus an optional `reason` and
`issuedAt` for the audit trail).

## Transports

```dart
abstract interface class ReleaseRuntimeTransport {
  Future<Uri?> start(ReleaseTransportStartRequest request);
  Future<void> stop();
}
```

`ReleaseTransportStartRequest` carries host, port, endpoint, timeout, body
ceiling, concurrency ceiling, and `accessToken`; its `toJson()` redacts the
token. Return the bound base URI, or `null` when the transport reserves no
endpoint.

| Transport | Use |
|---|---|
| `HttpReleaseRuntimeTransport` | Release default. Streamable HTTP on loopback. |
| `InertRuntimeTransport` | Tests and tooling: never binds, always succeeds. |

### `HttpReleaseRuntimeTransport` policy

| Concern | Setting |
|---|---|
| Protocol | `mcp_server` 3.1.1 `StreamableHttpServerTransport` (sessions, version negotiation, 2026-07-28 stateless path) |
| Fallback ports | `const []` — a taken port fails the start |
| Auth | `authToken` = the runtime's bearer token; 401 before dispatch |
| Origin | SDK loopback allow-list; `allowAnyOrigin: false`; foreign Origin → 403 |
| CORS | `Access-Control-Allow-Origin: http://<bound host>` (never `*`) |
| Responses | `isJsonResponseEnabled: true` (one request, one response) |
| GET stream | `enableGetStream: false` → 405 |
| Bounds | Request size, timeout, and session count from `ReleaseMcpConfig` |
