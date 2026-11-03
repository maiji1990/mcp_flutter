## 0.2.0 — unreleased (fork)

### Added

- `ReleaseMcpRuntime.http(...)`: a release-ready runtime backed by the
  Streamable HTTP transport (`mcp_server` 3.1.1).
- `HttpReleaseRuntimeTransport`: loopback MCP endpoint with bearer auth, Origin
  validation, JSON responses, and no fallback ports.
- `ReleaseAccessToken`: 256-bit `Random.secure()` token, constant-time
  `matches()`, redacted `toString()`, `Bearer` header helper.
- `ReleaseMcpRuntime.accessToken` and `rotateAccessToken()` (rotation is
  stop → rotate → start; see the doc comment).
- `ReleaseTransportStartRequest.accessToken`, with a redacted `toJson()`.
- `example/release_http_smoke.dart`: end-to-end handshake you can run on the
  computer.
- Tests: initialize + `tools/list` over a real socket, 401 (missing/wrong
  token), 403 (foreign Origin), 405 (GET), token non-leakage, port release on
  stop, rotation invalidating the old token, taken-port failure without
  rebinding.

### Changed

- `ReleaseMcpException` no longer accepts a free-form `message`; the message is
  fixed per code so a failure can never echo request data.
- `ReleaseMcpRuntime.config` is a public final field (was a getter).

## 0.1.0 — unreleased (fork)

### Added

- `ReleaseMcpRuntime`: opt-in lifecycle (`start` / `stop` / `dispose`) for an
  embedded MCP surface in release builds. All three are idempotent and
  serialized; nothing starts on construction.
- `ReleaseMcpConfig`: loopback-only bind, endpoint and budget validation, an
  `enabledOnStartup` hint that never auto-starts, and an explicit
  `allowNonLoopbackBinding` escape hatch.
- `ReleaseRuntimeState` / `ReleaseRuntimeLifecycle`: the
  `disabled → starting → running → stopping → disabled` machine, plus `error`
  with a recorded error code and a broadcast state stream.
- `ReleaseMcpErrorCode` / `ReleaseMcpException`: stable codes with categories,
  retryability, and HTTP-like statuses.
- `ReleasePermissionId` / `ReleasePermissionSet` / `ReleaseStartAuthorization`:
  the `ui:read`, `ui:interact`, `ui:capture`, and `app:<name>` consent model.
- `ReleaseRuntimeTransport` seam plus `InertRuntimeTransport`: the runtime could
  be wired into an app without opening a socket.
- `ReleaseRuntimeStatus`: read-only, redaction-safe snapshot stream.
