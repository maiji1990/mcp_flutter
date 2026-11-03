# `flutter_mcp_toolkit_release` API (PR-01)

Everything below is implemented and covered by `dart test`. Nothing in this file
describes a network endpoint: there is none yet.

## `ReleaseMcpRuntime`

```dart
ReleaseMcpRuntime({
  ReleaseMcpConfig config = const ReleaseMcpConfig(),
  ReleaseRuntimeTransport? transport,
})
```

Construction binds nothing, starts nothing, and reads no platform state.

| Member | Contract |
|---|---|
| `config` | The configuration the runtime was built with. |
| `state` | Current `ReleaseRuntimeState`. |
| `stateChanges` | Broadcast `Stream<ReleaseRuntimeState>`, emitted after commit. |
| `status` | Read-only `ReleaseRuntimeStatus` snapshot. |
| `statusChanges` | Broadcast `Stream<ReleaseRuntimeStatus>`. |
| `isDisposed` | True after `dispose()`. |
| `start({authorization})` | `Future<ReleaseRuntimeStatus>`. Idempotent. |
| `stop()` | `Future<ReleaseRuntimeStatus>`. Idempotent; safe from `error`. |
| `grantPermissions(ids)` | Adds consent while running. |
| `revokePermissions(ids)` | Withdraws consent while running; `ui:read` is structural and stays. |
| `dispose()` | Idempotent teardown; never throws. |

### `start` semantics

1. Disposed runtime → `runtime_disposed`.
2. Already `running` → returns the current status, transport untouched.
3. Invalid config → `invalid_config` with the failed `problems`; state stays
   `disabled`, transport untouched.
4. `readOnlyByDefault: false` and no `authorization` → `authorization_missing`.
5. Effective permissions are `{ui:read} ∪ authorization.grantedPermissions`.
6. Transport throws → state `error`, code `transport_start_failed`, session
   cleared, `ReleaseMcpException` rethrown.

Concurrent `start` / `stop` calls are queued: five simultaneous `start()` calls
produce exactly one transport start.

### `stop` / `dispose`

`stop` is a no-op while `disabled`; from `error` it re-enters `stopping` and
lands in `disabled` with the error code cleared. `dispose` stops the transport,
clears the session, closes both streams, and never throws — teardown paths must
not mask the original failure.

## `ReleaseMcpConfig`

| Field | Default | Rule |
|---|---|---|
| `host` | `127.0.0.1` | Loopback only (`127.0.0.1`, `::1`, `localhost`) unless `allowNonLoopbackBinding`. No schemes, paths, or `host:port`. |
| `port` | `8765` | `0..65535`; `0` requests an ephemeral port. |
| `endpoint` | `/mcp` | Absolute path, no query or fragment, `2..128` chars. |
| `enabledOnStartup` | `false` | Hint for the host app only; never auto-starts. |
| `readOnlyByDefault` | `true` | `false` makes a missing authorization an error. |
| `allowNonLoopbackBinding` | `false` | Explicit opt-in for LAN/public binds (not supported in V1). |
| `maxRequestBytes` | `1 MiB` | `1 KiB .. 8 MiB`. |
| `requestTimeout` | `30 s` | `> 0` and `<= 5 min`. |
| `maxConcurrentRequests` | `4` | `1..64`. |

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

## Permissions

`ui:read` · `ui:interact` · `ui:capture` · `app:<name>` where `<name>` matches
`^[a-z][a-z0-9._-]{0,63}$`.

`ReleasePermissionSet` is an immutable set with `union`, `difference`,
`contains`, `isReadOnly`, and a sorted `toWireList()` for stable JSON.
`ReleaseStartAuthorization` carries the grants (plus an optional `reason` and
`issuedAt` for the audit trail).

## `ReleaseRuntimeTransport`

```dart
abstract interface class ReleaseRuntimeTransport {
  Future<Uri?> start(ReleaseTransportStartRequest request);
  Future<void> stop();
}
```

Return the bound base URI, or `null` when the transport reserves no endpoint.
`InertRuntimeTransport` (the default) always returns `null` — that is what makes
PR-01 shippable without a socket.
