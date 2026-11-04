# Release runtime API (PR-01 … PR-03)

Everything below is implemented and covered by tests. MCP tools are the three
read-only UI tools; interaction, capture, and app actions are PR-04/PR-05.

## Packages

| Package | Contents |
|---|---|
| `flutter_mcp_toolkit_release` | Config, lifecycle, consent, bearer auth, HTTP transport, tool catalog, privacy filter. No Flutter SDK dependency. |
| `flutter_mcp_toolkit_release_flutter` | `FlutterReleaseUiSnapshotSource`: the semantic-tree adapter. Flutter only. |

## `ReleaseMcpRuntime`

```dart
ReleaseMcpRuntime({
  ReleaseMcpConfig config = const ReleaseMcpConfig(),
  ReleaseRuntimeTransport? transport,
  ReleaseAccessToken? accessToken,
  ReleaseToolSurface? tools,
})

factory ReleaseMcpRuntime.http({
  ReleaseMcpConfig config = const ReleaseMcpConfig(),
  ReleaseAccessToken? accessToken,
  ReleaseToolSurface? tools,
})
```

Construction binds nothing, starts nothing, and reads no platform state.

| Member | Contract |
|---|---|
| `config` | Public final field: the configuration the runtime was built with. |
| `state` / `stateChanges` | Lifecycle state and its broadcast stream. |
| `status` / `statusChanges` | Redaction-safe snapshot and its stream. |
| `accessToken` | Bearer secret; `toString()` is redacted. |
| `start({authorization})` / `stop()` / `dispose()` | Idempotent, serialized. |
| `grantPermissions(ids)` / `revokePermissions(ids)` | Consent changes while running. |
| `rotateAccessToken()` | New token; only while `disabled`. |

### Tool calls

If `tools` is supplied, `start()` hands the transport a **guarded** surface.
Before a call reaches the tool implementation the runtime checks, in order:

1. state is `running` → otherwise `runtime_not_running`;
2. the tool exists in the catalog → otherwise `tool_not_found`;
3. the session holds the tool's permission → otherwise `permission_denied`
   (details name the missing permission);
4. a handler that throws becomes `unknown_error` with the exception *type*
   only — never a stack trace.

Tool-level refusals travel as a normal result with `success: false` and
`error.code`, which the HTTP transport maps onto MCP `isError: true`.

## Read tools (v1)

| Tool | Arguments | Permission | Notes |
|---|---|---|---|
| `ui_get_tree` | `filter`, `maxNodes` (≤500), `maxDepth` (≤64) | `ui:read` | Flat node list in walk order; `truncated` when a budget bites. |
| `ui_get_current_page` | — | `ui:read` | Route name (if a provider is wired), surface, node count. Uses `peek`, so it never advances the snapshot id. |
| `ui_find_element` | `identifier`, `label`, `role` | `ui:read` | Exactly one match or a refusal; labels match case-insensitively. |

Every result carries `requestId`, `success`, `snapshotId` when applicable,
`data`, and `error` (`code`, `message`, `details`) on refusal.

Refusal codes: `invalid_argument`, `element_not_found`, `ambiguous_match`
(details list candidate refs), `tool_not_found`, `permission_denied`,
`runtime_not_running`, `unknown_error`.

## UI value types

`ReleaseUiNode` — `ref`, `id`, `type`, `identifier`, `label`, `value`,
`hint`, `actions`, `children`, `enabled`/`focused`/`checked`/`toggled`/
`selected`, `visibleInViewport`, `centerInViewport`, `bounds`, and the
release-only `sensitive`.

`ReleaseUiSnapshot` — `snapshotId`, `nodes`, `capturedAt`, `truncated`,
`interactionSurface`, `routeName`.

`ReleasePageInfo` — `snapshotId`, `routeName`, `interactionSurface`,
`nodeCount`, `capturedAt`.

`ReleaseRouteProvider` — `Future<String?> currentRouteName()`; backed by
whatever router the app uses (`CallbackReleaseRouteProvider` adapts a function).

## `ReleaseUiSnapshotSource`

```dart
abstract interface class ReleaseUiSnapshotSource {
  Future<ReleaseUiSnapshot> captureSnapshot({int? maxNodes, String? identifierPrefix});
  Future<ReleasePageInfo> readCurrentPage();
}
```

The one Flutter-shaped seam. Implementations must not retain `SemanticsNode`
objects beyond a capture and must return an empty snapshot, not throw, when the
tree is not ready.

## Privacy

```dart
abstract interface class ReleasePrivacyFilter {
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot);
}
```

`RedactingPrivacyFilter(maxTextLength: 160, maskAllValues: false, maskMarker: '••••')`
masks the value of every `sensitive` node (and every value when
`maskAllValues`), and truncates label/value/hint.

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

## Lifecycle

```
disabled → starting → running → stopping → disabled
                ↓        ↓         ↓
              error ←────┴─────────┘      (error → disabled | starting | stopping)
```

Illegal transitions throw `StateError`: they are programming errors.

## Errors

`ReleaseMcpException(code, {problems, details})` — `code`, `message`,
`category`, `retryable`, `httpLikeStatus`, `problems`, `details`. Messages are
fixed per code, so a failure can never echo request data or a token.

| Code | Category | HTTP-like |
|---|---|---|
| `invalid_config` | config | 400 |
| `invalid_argument` | validation | 400 |
| `invalid_permission_id` | permission | 400 |
| `authorization_missing` | permission | 403 |
| `permission_denied` | permission | 403 |
| `invalid_state_transition` | state | 409 |
| `ambiguous_match` | validation | 409 |
| `element_not_found` | state | 404 |
| `tool_not_found` | validation | 404 |
| `transport_start_failed` | transport | 503 |
| `transport_stop_failed` | transport | 503 |
| `runtime_not_running` | state | 409 |
| `runtime_disposed` | state | 409 |
| `unknown_error` | internal | 500 |

HTTP-level refusals come from the transport: 401 (bearer), 403 (foreign
`Origin`), 405 (GET), 413 (body over the ceiling).

## Transports

```dart
abstract interface class ReleaseRuntimeTransport {
  Future<Uri?> start(ReleaseTransportStartRequest request);
  Future<void> stop();
}
```

`ReleaseTransportStartRequest` carries host, port, endpoint, timeout, body
ceiling, concurrency ceiling, `accessToken`, and the guarded `toolSurface`; its
`toJson()` redacts the token and lists tool names only.

| Transport | Use |
|---|---|
| `HttpReleaseRuntimeTransport` | Release default. Streamable HTTP on loopback. |
| `InertRuntimeTransport` | Tests and tooling: never binds, always succeeds. |

### `HttpReleaseRuntimeTransport` policy

| Concern | Setting |
|---|---|
| Protocol | `mcp_server` 3.1.1 `StreamableHttpServerTransport` |
| Fallback ports | `const []` — a taken port fails the start |
| Auth | `authToken` = the runtime's bearer token; 401 before dispatch |
| Origin | SDK loopback allow-list; `allowAnyOrigin: false`; foreign Origin → 403 |
| CORS | `Access-Control-Allow-Origin: http://<bound host>` (never `*`) |
| Responses | `isJsonResponseEnabled: true` |
| GET stream | `enableGetStream: false` → 405 |
| Tools | Registered before the socket accepts; each call goes through the runtime's guard |
