# Release runtime (Android) — fork feature

This directory documents the fork-only `packages/release_runtime` package
(`flutter_mcp_toolkit_release`), which embeds a **guarded, opt-in MCP surface**
inside a *release* Flutter app so an external MCP client can drive the shipped
app over the loopback interface.

It exists because the upstream `mcp_toolkit` path is, by design, debug-only:
it needs the Dart VM Service, registers service extensions, and exposes eval and
hot reload. None of that exists in a release build, and none of it should.

## Status

| PR | Scope | State |
|---|---|---|
| 01 | Opt-in runtime package, public API, state machine, tests | **landed** |
| 02 | Streamable HTTP transport, auth, Origin, timeouts | not started |
| 03 | Semantic snapshot + refs + redaction | not started |
| 04 | Guarded interactions (mandatory `snapshotId`) | not started |
| 05 | App action registry + optional capture | not started |
| 06 | Android E2E, docs, compatibility matrix | not started |

Nothing in this directory claims release validation yet: PR-01 is a pure-Dart
package with no socket code, verified by `dart test` only. Android release
verification arrives with PR-02/PR-06.

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
- **Secure by default.** Loopback bind, read-only session, nothing bound on
  construction, stable error codes, no secrets in status or errors.
- **No debug capabilities in release.** Eval, hot reload, arbitrary file IO, and
  shell access are out of scope permanently, not "not yet implemented".

## Files

- [`api.md`](api.md) — the public API surface as implemented today.
- [`security.md`](security.md) — the security model, what is enforced now, and
  what PR-02 must add before the runtime may listen.
- [`upstream-sync.md`](upstream-sync.md) — how this fork tracks upstream
  `main` without carrying the patch on the mirror branch.

`android-deploy.md` (manifest permissions, `adb forward`, device matrix) is
written in PR-06, when there is a listener to point at.
