# Release runtime (Android) — fork feature

This directory documents the fork-only release runtime: two packages,
`flutter_mcp_toolkit_release` (transport, tools, policy) and
`flutter_mcp_toolkit_release_flutter` (the Flutter adapter that reads the
semantics tree). Together they embed a **guarded, opt-in MCP surface** inside a
*release* Flutter app so an external MCP client can observe it over loopback
HTTP.

It exists because the upstream `mcp_toolkit` path is, by design, debug-only:
it needs the Dart VM Service, registers service extensions, and exposes eval and
hot reload. None of that exists in a release build, and none of it should.

## Status

| PR | Scope | State |
|---|---|---|
| 01 | Opt-in runtime package, public API, state machine, tests | **landed** |
| 02 | Streamable HTTP transport, bearer auth, Origin, bounds | **landed** |
| 03 | Semantic snapshot, refs, redaction, read tools | **landed** (widget tests; no device yet) |
| 04 | Guarded interactions (mandatory `snapshotId`) | not started |
| 05 | App action registry + optional capture | **landed** |
| 06 | Android E2E, docs, compatibility matrix | not started |

## Business actions and capture

**Business actions** are declared by the app, not discovered by the client. Each
`ReleaseAppAction` carries a name (`pay.invoice`), a description, an argument
schema, and a handler; its permission is `app:<name>`, so consent is granted per
action rather than "the agent may do business things". One MCP tool,
`app_invoke_action`, fronts them all: the permission a call needs depends on the
`name` argument, which is why a tool definition can carry a resolver. An
unregistered name resolves to "no static permission" and is refused as
`action_not_found` — not as a misleading `permission_denied`. Actions are
serialized with each other.

**Capture** is the one tool whose output cannot be redacted after the fact. So
it is guarded three ways: `ui:capture` consent (never implied by `ui:read` or
`ui:interact`), a route policy evaluated *before* the frame is taken
(`ReleaseCapturePolicy`), and a byte budget (an encoded PNG of a phone screen is
megabytes; an oversized frame is refused, not truncated). Only PNG is produced
in v1 — the reused toolkit path encodes PNG; JPEG is refused as
`unsupported_format` rather than quietly returning PNG.

## Guarded interactions

A write tool (`ui_click`, `ui_set_text`, `ui_scroll`) needs three things at
once: `ui:interact`, the `ref`, **and** the `snapshotId` that issued it.

Why the id is mandatory: refs are positional strings re-issued by every
snapshot. Without the id, "click `s_3`" from thirty seconds ago clicks whatever
holds that position now. The runtime therefore checks, in order:

1. the snapshot is one this session published — otherwise `stale_snapshot`
   (`unknown_snapshot`);
2. it is still the newest, unused one — otherwise `stale_snapshot`
   (`superseded` / `consumed`);
3. the app still reports it as current — otherwise `stale_snapshot`
   (`app_moved_on`);
4. the ref exists in it — otherwise `unknown_ref`;
5. the node is attached, on screen, and enabled — otherwise
   `node_not_actionable` with the reason;
6. the node exposes the action — otherwise `unsupported_action`;
7. `ui_set_text` refuses sensitive (obscured) fields — `node_sensitive`.

Validation runs again **inside** the interaction queue, because the tree can
change while a call waits its turn. Calls are serialized: two clicks on one
snapshot produce exactly one tap and one `stale_snapshot`.

A successful call means *dispatched*, not *finished*. It consumes the snapshot,
so the next interaction needs a fresh `ui_get_tree` — which is also how a client
learns what its action did.

What "landed" means: `dart analyze` / `flutter analyze` clean, `dart test`
(79) and `flutter test` (5) green on Flutter 3.47.9 / Dart 3.13.7, plus a real
handshake and tool call over a real socket. It does **not** mean validated on an
Android device — that is PR-06.

## Reuse, not a second implementation

The UI tree comes from `mcp_toolkit`'s `SemanticSnapshotService`: one walk, one
ref vocabulary, so a ref means the same thing in a release build as in a debug
one. The release runtime adds exactly three things on top:

1. **Budgets** — `maxNodes` / `maxDepth` clamped in the runtime, so a client
   cannot ask for a tree large enough to stall the UI isolate.
2. **Redaction** — nodes whose semantics carry `SemanticsFlag.isObscured`
   (passwords, one-time codes) are flagged by the adapter and masked by
   `RedactingPrivacyFilter` before the payload is serialized.
3. **A permission boundary** — every tool declares the permission it needs, and
   the runtime refuses a call whose permission the session does not hold.

## Protocol baseline

The HTTP layer is the published `mcp_server` package, not a hand-rolled
implementation:

| Package | Released version | Why |
|---|---|---|
| `mcp_server` | 3.1.1 | Ships `StreamableHttpServerTransport` in the published archive: sessions, version negotiation, the 2026-07-28 stateless revision, bearer auth, Origin validation, body/timeout bounds. |
| `dart_mcp` | 0.5.2 | No HTTP transport dependency (`shelf`/`http` absent). Fine for the debug path, unusable for an in-app HTTP endpoint. |

If `dart_mcp` later gains equivalent HTTP support, the adapter boundary
(`ReleaseRuntimeTransport`) is where the swap happens; no tool or UI code
changes.

## Design constraints carried into the code

- **Two run paths, one vocabulary.** Debug keeps the VM Service path; this
  runtime exposes the same observe/act/verify vocabulary in release.
- **Transport is a seam, not a dependency.** `ReleaseRuntimeTransport` keeps
  sockets, auth, and timeouts out of the runtime.
- **Consent is explicit.** Read is structural; interaction, capture, and app
  actions need `ReleaseStartAuthorization` grants.
- **Authentication is not optional.** Loopback is not a trust boundary: other
  apps on the device can reach `127.0.0.1`.
- **Secure by default.** Loopback bind, read-only session, nothing bound on
  construction, no wildcard CORS, no fallback ports, no node text without
  redaction, stable error codes.
- **No debug capabilities in release.** Eval, hot reload, arbitrary file IO, and
  shell access are out of scope permanently.

## Files

- [`api.md`](api.md) — the public API surface as implemented today.
- [`security.md`](security.md) — what is enforced now and what is still
  missing before a device build may listen.
- [`upstream-sync.md`](upstream-sync.md) — how this fork tracks upstream
  `main`.

`android-deploy.md` (manifest permissions, `adb forward`, device matrix) is
written in PR-06.