# Release runtime API (v0.7.0)

Everything below is implemented and covered by tests. The catalog is the four
Flutter UI groups (read, interaction, app actions, capture), the optional
`web_*` WebView family, and the runtime's transport/lifecycle surface.

## Packages

| Package | Contents |
|---|---|
| `flutter_mcp_toolkit_release` | Config, lifecycle, consent, bearer auth, HTTP transport, tool catalog, privacy filter. No Flutter SDK dependency. |
| `flutter_mcp_toolkit_release_flutter` | `FlutterReleaseUiSnapshotSource`, the semantic-tree adapter, plus `AgentSensitive` / `ExcludeFromAgent`. Flutter only. |
| `flutter_mcp_toolkit_release_webview` | Optional WebView DOM adapter: registry, fixed scripts, navigation epochs. Flutter + `webview_flutter`. |

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
4. a dispatch slot is available (at most `maxConcurrentRequests`, at most 16
   waiting) → otherwise `server_busy`;
5. a handler that throws becomes `unknown_error` with the exception *type*
   only — never a stack trace.

The call also carries a `ReleaseCallAuthorization`: the epoch it started in and
a live probe into the grant set. Queues inside a tool re-consult the probe
immediately before dispatch, so consent withdrawn while a call waited refuses it
(`permission_denied`, details `reason: authorization_changed`).

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

## Write tools (v1)

| Tool | Arguments | Permission | Notes |
|---|---|---|---|
| `ui_click` | `ref`, `snapshotId` | `ui:interact` | Taps the node; needs the `tap` action. |
| `ui_set_text` | `ref`, `text`, `snapshotId` | `ui:interact` | Types into a `textField`; refuses `sensitive` nodes. |
| `ui_scroll` | `ref`, `direction` (up/down/left/right), `amount` (1..5000, default 300), `snapshotId` | `ui:interact` | Scrolls the node or its scrollable ancestor. |

`snapshotId` is **required** on all three: refs are positional strings that
every snapshot re-issues, so acting without the id means acting on whatever took
the node's place. A success answers `{"dispatched": true, "ref", "action"}` —
dispatched, not finished; the next `ui_get_tree` is how a client learns the
outcome.

Refusals specific to interactions:

| Code | When |
|---|---|
| `snapshot_required` | `snapshotId` missing |
| `stale_snapshot` | unknown / superseded / already consumed / the app moved on |
| `unknown_ref` | the ref is not in that snapshot |
| `node_not_actionable` | detached, off screen, disabled, unverifiable |
| `unsupported_action` | the node does not expose the action |
| `node_sensitive` | `ui_set_text` against an obscured field |
| `interaction_failed` | the UI refused or threw while performing |

### Serialization and consumption

Calls are queued: one interaction at a time, and the queue re-validates before
acting, because the tree can change while a call waits. A successful action
consumes the snapshot — a second call with the same id is `stale_snapshot`
(`consumed`) rather than a second tap.

`ui_find_element` publishes its own snapshot, so it supersedes a refs set from
an earlier `ui_get_tree`; `ui_get_current_page` deliberately does not.

## App actions

The app declares its own business actions; the client cannot invent one.

```dart
final action = ReleaseAppAction(
  name: 'pay.invoice',            // slug; also the app:pay.invoice permission
  description: 'Pay an invoice',
  inputSchema: <String, Object?>{'type': 'object', 'properties': <String, Object?>{'invoiceId': <String, Object?>{'type': 'string'}}},
  handler: (arguments) async => <String, Object?>{'status': 'paid'},
);

final tools = ReleaseAppActionTools(<ReleaseAppAction>[action]);
```

| Member | Contract |
|---|---|
| `name` | `^[a-z][a-z0-9._-]{0,63}$`, validated at construction. |
| `permission` | `app:<name>`, requiring explicit consent. |
| `handler` | Receives the `arguments` object; its return becomes `data.result`. |

One tool fronts them: `app_invoke_action` with `{name, arguments}`. The tool's
schema lists the registered names as an `enum`, and its required permission is
resolved per call:

```dart
ReleaseToolDefinition(
  name: 'app_invoke_action',
  permission: null,                      // dynamic
  permissionResolver: (args) => actions[args['name']]?.permission,
  ...
)
```

The schema is compiled when the action is constructed (an unusable schema
throws `ArgumentError` there) and enforced on every call: type, required and
extra properties (`additionalProperties: false`), enums, numeric and length
bounds, nested objects/arrays. Validation runs before the handler; failures are
`invalid_argument` with `details.fields` (paths only, never values). The
serialized `arguments` object is capped by `maxArgumentBytes` (64 KiB).

Refusals: `action_not_found` (unregistered — the resolver yields no permission,
so the surface answers), `invalid_argument` (missing name, non-object
arguments, schema mismatch, oversized arguments), `action_failed` (the handler
threw; details carry the exception type only), `permission_denied` (the
`app:<name>` grant was revoked while the call waited). Calls are serialized.

## WebView tools (v0.7.0, optional package)

```dart
final registry = ReleaseWebViewRegistry()
  ..register(
    viewId: 'order-h5',
    engine: WebViewFlutterEngine(controller),
    allowedOrigins: const <String>{'https://app.example.com'},
  );

final tools = ReleaseWebTools(source: WebViewDomReleaseSource(registry));
```

| Tool | Arguments | Permission | Notes |
|---|---|---|---|
| `web_list_views` | — | `web:read` | Only registered views. |
| `web_get_tree` | `viewId`, `maxNodes` (≤500), `maxDepth` (≤64) | `web:read` | Bounded DOM snapshot; text of secret fields masked. |
| `web_find_element` | `viewId`, `role`, `tag`, `text` | `web:read` | Up to five matches from a fresh snapshot. |
| `web_get_state` | `viewId` | `web:read` | Sanitized URL (origin + path), epoch, loading. |
| `web_click` | `viewId`, `ref`, `snapshotId` | `web:interact` | Dispatches `.click()` inside the page. |
| `web_set_text` | `viewId`, `ref`, `snapshotId`, `text` (≤4096) | `web:interact` | Uses the prototype setter so frameworks observe it; refuses sensitive fields. |
| `web_scroll` | `viewId`, `ref`, `snapshotId`, `direction`, `amount` (≤5000) | `web:interact` | Scrolls the page or a scroll container. |

There is no JavaScript-evaluation tool. Snapshot ids are
`web:<viewId>:<navigationEpoch>:<nonce>`; a ref from another epoch, another
snapshot, or an unregistered origin is refused. See
[`webview.md`](webview.md) for the page-side rules and limits.

## Capture

```dart
final tools = ReleaseCaptureTools(
  source: FlutterReleaseUiCaptureSource(routeProvider: myRouteProvider),
  policy: const ReleaseCapturePolicy(
    allowedRoutes: <String>{'/home'},     // capture is opt-in per route
    blockedRoutes: <String>{'/wallet'},   // and a block always wins
  ),
  maxBytes: 1536 * 1024,
);
```

`ui_capture` takes `scale` (0.1..3, default 1) and `format` (`png`; `jpeg`
answers `unsupported_format`). Order of checks: permission `ui:capture` →
argument validation → live consent → route policy → capture → route re-read →
byte budget.

`ReleaseCapturePolicy()` with no arguments captures **nothing**: `allowedRoutes`
is empty and `allowWhenRouteUnknown` is false. `blockedRoutes` always wins over
`allowedRoutes`.

| Refusal | When |
|---|---|
| `route_blocked` | `ReleaseCapturePolicy` rejects the current route (checked **before** the frame) |
| `route_changed` | the route changed during capture; the frame is discarded, no bytes are returned |
| `capture_unavailable` | nothing painted, protected content, or the source threw |
| `capture_too_large` | encoded image over `maxBytes` (details: size, limit, dimensions) |

Success returns `mimeType`, `width`, `height`, `byteLength`, `scale`, and
`bytesBase64`.

```dart
abstract interface class ReleaseUiCaptureSource {
  Future<String?> currentRouteName();
  Future<ReleaseCaptureResult?> capture(ReleaseCaptureRequest request);
}
```

Returning null means "cannot capture", never "here is a blank image".

## `ReleaseSnapshotStore`

```dart
final store = ReleaseSnapshotStore(capacity: 4);
store.publish(snapshot);      // ui_get_tree / ui_find_element do this
store.isUsable(snapshotId);   // latest and unused
store.nodeById(snapshotId, ref);
store.consumeLatest();        // after a successful interaction
```

## `ReleaseUiInteractionDriver`

```dart
abstract interface class ReleaseUiInteractionDriver {
  Future<bool> isSnapshotCurrent(String snapshotId);
  Future<String?> currentRouteName();
  Future<ReleaseUiNodeState> inspect(String ref);
  Future<ReleaseDriverResult> tap(String ref);
  Future<ReleaseDriverResult> setText(String ref, String text);
  Future<ReleaseDriverResult> scroll(String ref, ReleaseScrollDirection direction, {double amount});
}
```

`ReleaseUiNodeState`: `attached`, `detached`, `hidden`, `disabled`,
`unknown`. `ReleaseDriverResult` carries `ok`, a short non-sensitive `error`
token, and non-sensitive `details` (for example `via: semantic_action`).

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
final class ReleaseUiPrivacyPolicy {
  const ReleaseUiPrivacyPolicy({
    Set<String> deniedRoutes,     // refuse the page: route_denied
    Set<String> maskedRoutes,     // keep the tree, mask every field
    Set<String> deniedIdentifiers,// remove node + subtree
    Set<String> maskedIdentifiers,
    Set<String> deniedTypes,
    bool maskAllValues,
    bool maskSensitiveLabels = true,
    bool denyWhenRouteUnknown = false,
  });
}

abstract interface class ReleasePrivacyFilter {
  ReleasePrivacyDecision routeDecision(String? routeName);
  ReleasePrivacyVerdict screen(ReleaseUiSnapshot snapshot); // snapshot or refusal
  ReleaseUiSnapshot apply(ReleaseUiSnapshot snapshot);      // already-checked path
}
```

`RedactingPrivacyFilter(maxTextLength: 160, maskAllValues: false,
maskMarker: '••••', policy: ReleaseUiPrivacyPolicy())` masks `label`,
`value`, and `hint` of every `sensitive` node, applies the page/node policy,
and truncates long text. A denied route yields `ReleasePrivacyVerdict.denied`
(`route_denied`, `reason: sensitive_route`) before any node is serialized.

Widget-level intent lives in `flutter_mcp_toolkit_release_flutter`:
`AgentSensitive(child: ...)` sets `Semantics.obscured`, and
`ExcludeFromAgent(child: ...)` removes the subtree from semantics.

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
| `maxConcurrentRequests` | `4` | `1..64`; the transport's request budget. |
| `maxSessions` | `32` | `1..256`; concurrent MCP sessions the server keeps. Decoupled from `maxConcurrentRequests` after device testing showed four clients locking out the fifth. |
| `sessionIdleTimeout` | `10 min` | `30 s .. 24 h`; an unused session is freed, so a client that never sends `DELETE` cannot exhaust `maxSessions`. |

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
| `action_not_found` | validation | 404 |
| `action_failed` | execution | 500 |
| `capture_unavailable` | capability | 501 |
| `capture_too_large` | validation | 413 |
| `route_blocked` | permission | 403 |
| `route_denied` | permission | 403 |
| `route_changed` | state | 409 |
| `invalid_schema` | config | 400 |
| `server_busy` | transport | 429 |
| `origin_denied` | permission | 403 |
| `view_not_found` | validation | 404 |
| `unsupported_format` | validation | 415 |
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