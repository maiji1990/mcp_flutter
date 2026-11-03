# Release runtime (Android) — fork feature

This directory documents the fork-only `packages/release_runtime` package
(`flutter_mcp_toolkit_release`), which embeds a **guarded, opt-in MCP surface**
inside a *release* Flutter app so an external MCP client can drive the shipped
app over loopback HTTP.

It exists because the upstream `mcp_toolkit` path is, by design, debug-only:
it needs the Dart VM Service, registers service extensions, and exposes eval and
hot reload. None of that exists in a release build, and none of it should.

## Status

| PR | Scope | State |
|---|---|---|
| 01 | Opt-in runtime package, public API, state machine, tests | **landed** |
| 02 | Streamable HTTP transport, bearer auth, Origin, bounds | **landed** (unit + loopback integration; no device yet) |
| 03 | Semantic snapshot + refs + redaction | not started |
| 04 | Guarded interactions (mandatory `snapshotId`) | not started |
| 05 | App action registry + optional capture | not started |
| 06 | Android E2E, docs, compatibility matrix | not started |

What "landed" means here: `dart analyze` clean, `dart test` green on
Flutter 3.47.9 / Dart 3.13.7, and a real handshake over a real socket
(`example/release_http_smoke.dart`). It does **not** mean validated on an
Android device — that is PR-06.

## Protocol baseline

The HTTP layer is the published `mcp_server` package, not a hand-rolled
implementation. The choice is deliberate and version-pinned:

| Package | Released version | Why |
|---|---|---|
| `mcp_server` | 3.1.1 | Ships `StreamableHttpServerTransport` in the published archive: sessions, protocol-version negotiation, the 2026-07-28 stateless revision, bearer auth, Origin validation, body/timeouts bounds. |
| `dart_mcp` | 0.5.2 | No HTTP transport dependency (`shelf`/`http` absent from its pubspec). Fine for the debug path, unusable for an in-app HTTP endpoint. |

The plan's warning is honored: the decision is based on the **published**
archives, inspected after `pub get` — not on upstream `main` source. If
`dart_mcp` later gains equivalent HTTP support, the adapter boundary
(`ReleaseRuntimeTransport`) is where the swap happens; no UI or tool code
changes.

## Design constraints carried into the code

- **Two run paths, one vocabulary.** Debug keeps the VM Service path; this
  runtime exposes the same observe/act/verify vocabulary in release. The UI
  services are reused rather than re-implemented — a second UI-tree
  implementation would drift from the one the debug tools already exercise.
- **Transport is a seam, not a dependency.** `ReleaseRuntimeTransport` keeps
  sockets, auth, and timeouts out of the runtime, so the runtime can be tested
  (and shipped inert) without a network surface.
- **Consent is explicit.** Read is structural; interaction, capture, and app
  actions need `ReleaseStartAuthorization` grants.
- **Authentication is not optional.** Loopback is not a trust boundary: other
  apps on the device can reach `127.0.0.1`.
- **Secure by default.** Loopback bind, read-only session, nothing bound on
  construction, no wildcard CORS, no fallback ports, stable error codes, no
  secrets in status or errors.
- **No debug capabilities in release.** Eval, hot reload, arbitrary file IO, and
  shell access are out of scope permanently, not "not yet implemented".

## Files

- [`api.md`](api.md) — the public API surface as implemented today.
- [`security.md`](security.md) — what is enforced now and what is still
  missing before a device build may listen.
- [`upstream-sync.md`](upstream-sync.md) — how this fork tracks upstream
  `main` without carrying the patch on the mirror branch.

`android-deploy.md` (manifest permissions, `adb forward`, device matrix) is
written in PR-06.
