## 0.5.0 — unreleased (fork)

### Added

- `app_invoke_action`: one tool over the app's registered `ReleaseAppAction`s,
  each gated by its own `app:<name>` permission. Unknown names are
  `action_not_found` (the resolver yields no static permission, so the surface
  answers); throwing handlers become `action_failed` with the exception type
  only; calls are serialized.
- `ReleaseToolDefinition.permission` is now optional and can be computed per
  call with `permissionResolver` / `permissionFor(arguments)`.
- `ui_capture`: PNG screenshot behind `ui:capture`, a route policy evaluated
  before capture, and a byte budget. Scale (0.1..3) and format are validated
  before any UI work.
- `ReleaseUiCaptureSource` / `ReleaseCaptureRequest` /
  `ReleaseCaptureResult` / `ReleaseCaptureFormat` / `ReleaseCapturePolicy`.
- New codes: `action_not_found`, `action_failed`, `capture_unavailable`,
  `capture_too_large`, `route_blocked`, `unsupported_format`; new
  `capability` category.
- Tests: action registry/permissions/serialization, capture policy/budget/
  validation, and the HTTP round trip for both (permission gate, consent, base64
  payload).

## 0.4.0 — unreleased (fork)

### Added

- Write tools `ui_click`, `ui_set_text`, `ui_scroll`, all requiring
  `ui:interact` **and** the `snapshotId` that issued the ref.
- `ReleaseSnapshotStore`: publishes snapshots, tracks the current unused one,
  and consumes it after an action so a second call cannot re-tap a stale ref.
- `ReleaseUiInteractionDriver` contract (`isSnapshotCurrent`, `inspect`,
  `tap`, `setText`, `scroll`) plus `ReleaseUiNodeState` and
  `ReleaseDriverResult`.
- `ReleaseToolbox`: composes read and write surfaces into one, refusing
  duplicate tool names.
- `ReleaseReadTools` publishes what it returns, so only refs the client saw can
  be acted on.
- Serialized interaction queue with in-queue re-validation; concurrent calls on
  one snapshot yield exactly one action and one `stale_snapshot`.
- Driver failure mapping to stable codes (`node_not_actionable`,
  `stale_snapshot`, `unsupported_action`, `interaction_failed`) without
  forwarding driver prose.
- New codes: `snapshot_required`, `stale_snapshot`, `unknown_ref`,
  `node_not_actionable`, `unsupported_action`, `node_sensitive`,
  `interaction_failed`; new `execution` category.
- Tests: 30 interaction cases plus the HTTP round trip (permission gate, click,
  consumption, sensitive refusal, schema rejection).

## 0.3.0 — unreleased (fork)

## 0.3.0 — unreleased (fork)

### Added

- Read-only UI tools: `ui_get_tree`, `ui_get_current_page`,
  `ui_find_element`, all gated on `ui:read`.
- `ReleaseToolSurface` / `ReleaseToolDefinition` / `ReleaseToolCallResult`:
  transport-neutral tool catalog and the uniform `{success, requestId,
  snapshotId, data, error}` envelope.
- `ReleaseMcpRuntime(tools: …)`: tool calls are guarded by state, catalog
  membership, and the session's permissions before a handler runs.
- `ReleaseUiSnapshotSource`, `ReleaseUiNode`, `ReleaseUiSnapshot`,
  `ReleasePageInfo`: the Flutter-shaped seam and its value types.
- `ReleasePrivacyFilter` / `RedactingPrivacyFilter`: masks sensitive values,
  truncates long text, optional blanket value masking.
- `ReleaseRouteProvider` / `CallbackReleaseRouteProvider`: pluggable page name,
  independent of Navigator 1.0.
- `HttpReleaseRuntimeTransport` registers the tool catalog before the socket
  accepts, and maps `success: false` onto MCP `isError`.
- New error codes: `tool_not_found`, `element_not_found`,
  `ambiguous_match`, `invalid_argument`, plus the `validation` category.
- Flutter adapter package `flutter_mcp_toolkit_release_flutter` reusing
  `mcp_toolkit`'s `SemanticSnapshotService`, with obscured-node detection and
  5 widget tests.

## 0.2.0 — unreleased (fork)

### Added

- `ReleaseMcpRuntime.http(...)`: a release-ready runtime backed by the
  Streamable HTTP transport (`mcp_server` 3.1.1).
- `HttpReleaseRuntimeTransport`: loopback MCP endpoint with bearer auth, Origin
  validation, JSON responses, and no fallback ports.
- `ReleaseAccessToken`: 256-bit `Random.secure()` token, constant-time
  `matches()`, redacted `toString()`, `Bearer` header helper.
- `ReleaseMcpRuntime.accessToken` and `rotateAccessToken()`.
- Tests: initialize + `tools/list` over a real socket, 401/403/405, token
  non-leakage, port release, rotation, taken-port failure without rebinding.

## 0.1.0 — unreleased (fork)

### Added

- `ReleaseMcpRuntime`: opt-in idempotent lifecycle (`start` / `stop` /
  `dispose`); nothing starts on construction.
- `ReleaseMcpConfig`: loopback-only bind, endpoint and budget validation.
- `ReleaseRuntimeState` / `ReleaseRuntimeLifecycle`: state machine + stream.
- `ReleaseMcpErrorCode` / `ReleaseMcpException`: stable codes, fixed messages.
- `ReleasePermissionId` / `ReleasePermissionSet` / `ReleaseStartAuthorization`.
- `ReleaseRuntimeTransport` seam plus `InertRuntimeTransport`.