# Release runtime security model

Status: the defaults below are **implemented** in PR-01; the wire-level controls
(authentication, Origin checks, rate limiting) are **required before PR-02 may
listen** and are listed so the gap stays explicit.

## Implemented (PR-01)

| Control | Implementation |
|---|---|
| Off by default | Construction binds nothing; `start()` is an explicit call. |
| Loopback-only | `ReleaseMcpConfig.validate()` rejects non-loopback hosts unless `allowNonLoopbackBinding` is set. |
| Read-only session | Only `ui:read` is granted implicitly; interaction, capture, and app actions need consent. |
| No silent downgrade | `readOnlyByDefault: false` + missing authorization → `authorization_missing`. |
| Consent withdrawal | `revokePermissions()`; `ui:read` is structural, so end the session with `stop()` instead. |
| No secret leakage | Errors carry codes, field names, and error *types* only; `status`/`config` JSON has no token field. |
| Bounded surface | Request size, timeout, and concurrency ceilings live in config and are validated. |
| No debug capabilities | No eval, no hot reload, no arbitrary file IO, no shell — absent by construction, not by policy. |

## Required before the runtime listens (PR-02)

- **Authentication on every request.** Loopback is not a trust boundary: other
  apps on the device can reach `127.0.0.1`. Token generated from a cryptographic
  RNG, rotated/revocable, stored in Android Keystore-backed storage where
  available, **never** compiled into the APK and never logged.
- **Header-only credentials.** Never accept the token via query string; redact it
  from the audit log.
- **Origin and Host validation** for Streamable HTTP, plus `Content-Type` and
  body/header consistency checks. No wildcard CORS; no LAN or public binding by
  default.
- **Rate limiting and timeouts** enforced by the transport, mapped onto the
  error codes already defined here (`transport_start_failed` is not a substitute
  for a per-request 429/408).
- **Audit log** of tool calls with argument *shapes*, not values.

## Non-goals (permanent)

Dart expression evaluation, hot reload/restart, VM introspection, arbitrary file
IO, and shell execution. A release build has no legitimate reason to expose
them, so they are excluded from the tool catalog rather than permission-gated.

## Platform limits (to be tested on device in PR-06)

Foreground-only: lock screen, process death, and long-running background service
are out of scope for V1. A foreground service would need its own system-version
and store-policy review. PlatformViews, off-screen list items, and protected
content are not guaranteed to be visible to the semantics-based tools.
