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
- `ReleaseRuntimeTransport` seam plus `InertRuntimeTransport`: the runtime can be
  wired into an app today without opening a socket. The HTTP transport ships in
  PR-02.
- `ReleaseRuntimeStatus`: read-only, redaction-safe snapshot stream.

### Notes

- No MCP tool catalog, no HTTP server, and no MCP SDK dependency in this release.
- The upgrade path is deliberate: PR-02 adds the Streamable HTTP transport behind
  `ReleaseRuntimeTransport`; PR-03+ add the tools.
