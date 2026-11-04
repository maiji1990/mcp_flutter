# Release runtime security model

Status: the controls below are **implemented** in PR-01…PR-03 and covered by
tests. The gaps that must close before an Android release build is called
"verified" are listed separately — they are not silently assumed.

## Implemented

| Control | Implementation |
|---|---|
| Off by default | Construction binds nothing; `start()` is an explicit call. |
| Loopback-only | `ReleaseMcpConfig.validate()` rejects non-loopback hosts unless `allowNonLoopbackBinding` is set. |
| Bearer auth on every request | `HttpReleaseRuntimeTransport` passes `authToken` to the SDK transport, which answers 401 before dispatch. Loopback is *not* a trust boundary. |
| Constant-time comparison | SDK `_validateBearerToken` + `ReleaseAccessToken.matches`; no byte-by-byte early exit. |
| Token handling | 256 bits from `Random.secure()`; header-only (never a query string); `toString()` redacted; excluded from `status`/`config`/`details` JSON; `ReleaseTransportStartRequest.toJson()` redacts it. |
| Token rotation | `rotateAccessToken()` while stopped; the old token is refused after restart (tested). |
| Origin validation | SDK loopback allow-list, `allowAnyOrigin: false`; foreign `Origin` → 403 (tested). |
| No wildcard CORS | `CorsConfig(allowOrigin: 'http://<host>')`. |
| No silent rebinding | `fallbackPorts: const []`; a taken port is a failed start (tested). |
| Request bounds | Body ceiling, per-request timeout, and max sessions from config; SDK enforces. |
| Per-tool permission gate | Every `ReleaseToolDefinition` names a permission; the runtime refuses a call the session does not hold, before the handler runs (tested both ways). |
| Redaction before serialization | `RedactingPrivacyFilter` masks the value of every `sensitive` node (obscured semantics: passwords, OTPs), can mask all values, and truncates long text. Tested through a widget-test app and over HTTP. |
| Node budgets | `maxNodes` ≤ 500 and `maxDepth` ≤ 64 clamped in the runtime, so a client cannot request a tree that stalls the UI isolate. |
| Read-only session | Only `ui:read` is granted implicitly; interaction, capture, and app actions need consent. |
| No silent downgrade | `readOnlyByDefault: false` + missing authorization → `authorization_missing`. |
| Consent withdrawal | `revokePermissions()`; `ui:read` is structural, so end the session with `stop()`. |
| Snapshot-scoped refs | Every interaction requires the `snapshotId` that issued its ref, must match the store's current unused snapshot and the app's current snapshot, and the snapshot is consumed on success (tested: one tap, then `stale_snapshot`). |
| Serialized interactions | One write at a time, re-validated inside the queue, so a tree that changed while a call waited cannot be acted on. |
| Sensitive input is never driven | `ui_set_text` refuses nodes flagged `sensitive` (obscured semantics) with `node_sensitive`, before any driver call. |
| Per-action consent | Every business action needs its own `app:<name>` grant; one consent is not a blanket permission. Unregistered names are refused by the surface. |
| Capture needs its own consent | `ui:capture` is never implied by `ui:read`/`ui:interact`; without it the call is `permission_denied`. |
| Capture route policy | Blocked routes are refused **before** the frame is painted, because pixels cannot be redacted afterwards. |
| Capture size budget | Oversized frames are refused (`capture_too_large`) rather than truncated, so a client never receives a silent crop. |
| No secret leakage in errors | Messages are fixed per code; details carry field names, counts, refs, and error *types* only. A throwing handler becomes `unknown_error` without a stack trace or message text (tested). |
| No debug capabilities | No eval, no hot reload, no arbitrary file IO, no shell — absent by construction. |

## Redaction limits (documented, not hidden)

`sensitive` is derived from `SemanticsFlag.isObscured`, which Flutter sets for
`TextField(obscureText: true)` and anything else that marks its semantics
obscured. A custom widget that renders a secret without that flag is **not**
detectable from the tree; use `RedactingPrivacyFilter(maskAllValues: true)` as
a blanket policy, or mark the widget's semantics in the app.

Screenshots are a different problem: pixels cannot be redacted by a JSON filter.
Capture is not implemented yet (PR-05), and when it lands it must refuse capture
on sensitive routes or mask before encoding.

## Verified on a device (PR-06)

A release APK (`flutter build apk --release`, Flutter 3.47.9) was installed on a
Huawei PTP-AN10 / Android 17 (API 37) and driven from a computer over
`adb forward`:

- nothing answers before the user enables access; a request without the bearer
  token answers 401;
- `initialize` reports `flutter_mcp_toolkit_release 0.6.0`; `tools/list` shows
  the eight tools;
- `ui_get_tree`, `ui_click` (counter changed), `ui_set_text` (value read back),
  `ui_scroll`, `app_invoke_action`, and `ui_capture` (512x1120 PNG) all worked;
- `ui_capture` answered `route_blocked` on the demo's `/wallet` screen;
- a click without `snapshotId` was refused.

Device testing also found a real defect: the server capped MCP *sessions* by
`maxConcurrentRequests` (4), so the fifth client run was refused with "Too many
sessions". Sessions now have their own budget (`maxSessions`, default 32) and an
idle timeout (10 minutes), with a regression test that opens six sessions.

## Still required before a device build may listen (PR-04+ / PR-06)

- **Keystore-backed token storage.** The token lives in memory today. Persisting
  it across launches needs an Android Keystore-backed store behind a small
  interface; `SharedPreferences` would put the secret in app-readable storage.
- **Revocation UI semantics.** Rotation is stop → rotate → start; a "revoke
  access" action should also drop any persisted token and stop the runtime.
- **Rate limiting.** The SDK ships a rate limiter, but the runtime does not wire
  it yet: a local client can issue requests as fast as the timeout allows.
- **Audit log.** No call log exists yet. When interaction tools land, log tool
  name, session id, permission decision, and argument *shapes* (never values),
  with the token redacted.
- **Device test matrix.** No Android device run yet: foreground/background
  transitions, rotation, dialogs, back navigation, process death, and the
  minimum supported API level are all unverified.

## Non-goals (permanent)

Dart expression evaluation, hot reload/restart, VM introspection, arbitrary file
IO, and shell execution. A release build has no legitimate reason to expose
them, so they are excluded from the tool catalog rather than permission-gated.

## Platform limits (to be tested on device in PR-06)

Foreground-only: lock screen, process death, and long-running background service
are out of scope for V1. A foreground service would need its own system-version
and store-policy review. PlatformViews, off-screen list items, and protected
content are not guaranteed to be visible to the semantics-based tools.