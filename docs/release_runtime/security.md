# Release runtime security model

Status: the controls below are **implemented** in PR-01/PR-02 and covered by
tests. The gaps that must close before an Android release build is called
"verified" are listed separately — they are not silently assumed.

## Implemented

| Control | Implementation |
|---|---|
| Off by default | Construction binds nothing; `start()` is an explicit call. |
| Loopback-only | `ReleaseMcpConfig.validate()` rejects non-loopback hosts unless `allowNonLoopbackBinding` is set. |
| Bearer auth on every request | `HttpReleaseRuntimeTransport` passes `authToken` to the SDK transport, which answers 401 before dispatch. Loopback is *not* treated as a trust boundary. |
| Constant-time comparison | SDK `_validateBearerToken` + `ReleaseAccessToken.matches`; no byte-by-byte early exit. |
| Token entropy and handling | 256 bits from `Random.secure()`; header-only (never a query string); `toString()` redacted; excluded from `status`/`config`/`details` JSON; `ReleaseTransportStartRequest.toJson()` redacts it. |
| Token rotation | `rotateAccessToken()` while stopped; the old token is refused after restart (tested). |
| Origin validation | SDK loopback allow-list, `allowAnyOrigin: false`; foreign `Origin` → 403 (tested). |
| No wildcard CORS | `CorsConfig(allowOrigin: 'http://<host>')`. |
| No silent rebinding | `fallbackPorts: const []`; a taken port is a failed start (tested). |
| Request bounds | Body ceiling, per-request timeout, and max sessions come from config; SDK enforces. |
| Read-only session | Only `ui:read` is granted implicitly; interaction, capture, and app actions need consent. |
| No silent downgrade | `readOnlyByDefault: false` + missing authorization → `authorization_missing`. |
| Consent withdrawal | `revokePermissions()`; `ui:read` is structural, so end the session with `stop()`. |
| No secret leakage in errors | Messages are fixed per code; details carry field names and error *types* only. |
| No debug capabilities | No eval, no hot reload, no arbitrary file IO, no shell — absent by construction, not by policy. |

## Still required before a device build may listen (PR-03+ / PR-06)

- **Keystore-backed token storage.** The token lives in memory today. Persisting
  it across launches (so a client does not need a new pairing code every start)
  needs an Android Keystore-backed store behind a small interface; a plain
  `SharedPreferences` write would put the secret in app-readable storage.
- **Revocation UI semantics.** Rotation is stop → rotate → start; a "revoke
  access" button should also drop the persisted token and stop the runtime.
- **Rate limiting.** The SDK ships a rate limiter, but the runtime does not wire
  it yet: a local client can issue requests as fast as the timeout allows. Add
  a per-session budget and map exhaustion to 429.
- **Audit log.** No call log exists yet. When the tool catalog lands, log tool
  name, session id, permission decision, and argument *shapes* (never values),
  with the token redacted.
- **Screenshot redaction.** `ui_capture` (PR-05) cannot be made safe by JSON
  redaction; sensitive routes must refuse capture or be masked before encoding.
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
