# Release runtime (Android) — fork feature

This directory documents the fork-only release runtime: three packages,
`flutter_mcp_toolkit_release` (transport, tools, policy),
`flutter_mcp_toolkit_release_flutter` (the Flutter adapter that reads the
semantics tree), and the optional `flutter_mcp_toolkit_release_webview` (DOM
access for app-owned WebViews). Together they embed a **guarded, opt-in MCP
surface** inside a *release* Flutter app so an external MCP client can observe it
over loopback HTTP.

It exists because the upstream `mcp_toolkit` path is, by design, debug-only:
it needs the Dart VM Service, registers service extensions, and exposes eval and
hot reload. None of that exists in a release build, and none of it should.

## Status

| PR | Scope | State |
|---|---|---|
| 01 | Opt-in runtime package, public API, state machine, tests | **landed** |
| 02 | Streamable HTTP transport, bearer auth, Origin, bounds | **landed** |
| 03 | Semantic snapshot, refs, redaction, read tools | **landed** |
| 04 | Guarded interactions (mandatory `snapshotId`) | **landed** |
| 05 | App action registry + capture | **landed** |
| 06 | Android E2E, docs, compatibility matrix | **landed** (release APK on Android 17) |
| 07 | Full-field privacy policy and route-level read denial (SEC-01) | **landed** |
| 08 | Authorization epoch, queued-consent re-check, stop cancellation (AUTH-01) | **landed** |
| 09 | Action JSON Schema enforcement, capture allow-list + navigation re-check (ACT-01, CAP-01/02) | **landed** |
| 10 | Snapshot/navigation consistency, concurrency budget, CI, docs (UI-01, NET-01, CI-01, DOC-01, META-01) | **landed** (device-verified 2026-11-04) |
| W01 | Optional WebView adapter package + explicit controller registry | **landed** (device-verified 2026-11-04) |
| W02 | `web_get_tree` / `web_find_element` with DOM privacy | **landed** (device-verified 2026-11-04) |
| W03 | `web_click` / `web_set_text` / `web_scroll` with epoch/ref checks | **landed** (device-verified 2026-11-04) |
| W04 | Hybrid capture verification, SPA/iframe tests, device matrix | **partial** (DOM flow device-verified; hybrid/SPA/iframe not) |

What "landed" means here: `dart analyze` / `flutter analyze` clean,
`dart test` (179), `flutter test` (13) for the Flutter adapter, and
`flutter test` (28) for the WebView package, all green on Flutter 3.47.9 /
Dart 3.13.7.

### Device run — 2026-11-04

A release APK (18.4 MB) was installed on a **Huawei PTP-AN10, Android 17
(API 37), arm64** and driven over `adb forward` with
`tool/mcp_smoke.dart --webview-check --wallet-check`; every step passed:

- `initialize` reports `0.7.0` and `tools/list` returns the 8 Flutter tools
  plus the 7 `web_*` tools;
- read, click, text entry, scroll, action invocation, and a 512x1120 PNG
  capture work; invalid action arguments are refused before the handler;
- `/wallet` reads answer `route_denied` with no card number, and capture on it
  is `route_blocked` with no bytes;
- a locally served H5 page inside a real `WebViewWidget` is listed, read (PIN
  masked), filled, clicked, and re-read (`Result for INV-42`); replaying the
  consumed snapshot is `stale_snapshot`, and `ui_capture` on `/web-demo` is
  `route_blocked`.

Two hardware-only defects were found and fixed: Android's double-encoded
`evaluateJavascript` result, and a Dart `\s` escape that reached the page
script as `s`. Both now have regression tests.

See [`security_review_and_webview_plan.md`](security_review_and_webview_plan.md)
for the finding-by-finding status, including what is still open.

## Privacy policy (SEC-01)

Redaction is not only about `obscureText`. A card number is usually a plain
`Text` widget, and semantics cannot tell a secret from a slogan. The runtime
therefore takes a **policy**, evaluated in the process before anything is
serialized:

```dart
ReleaseReadTools(
  source: FlutterReleaseUiSnapshotSource(routeProvider: myRoutes),
  privacy: const RedactingPrivacyFilter(
    policy: ReleaseUiPrivacyPolicy(
      deniedRoutes: <String>{'/wallet'},   // refuse these pages outright
      maskedRoutes: <String>{'/profile'},  // keep the tree, mask every field
      deniedIdentifiers: <String>{'internal_notes'},
      denyWhenRouteUnknown: true,          // cannot prove it is safe → refuse
    ),
  ),
);
```

Rules:

| Rule | Effect |
|---|---|
| `sensitive` node (obscured semantics or `AgentSensitive`) | `label`, `value`, and `hint` are all masked — not only the value. |
| `deniedRoutes` | The whole read is refused with `route_denied`; no node text is built into a payload. |
| `maskedRoutes` | The tree is returned, every text field is masked. |
| `deniedIdentifiers` / `deniedTypes` | The node and its subtree are removed from the snapshot. |
| `maskAllValues` | Every text field is masked, for "no field text ever" apps. |

The Flutter adapter adds two wrappers for widget-level intent:
`AgentSensitive` (sets `Semantics.obscured`, so the node is flagged and masked)
and `ExcludeFromAgent` (removes the subtree from semantics entirely).

Refusals never quote node text: the denial is a fixed message plus a stable
`reason` token (`sensitive_route`).

## Guarded interactions and consent epochs (AUTH-01 / UI-01)

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
4. the app is still on the route the snapshot was taken on — otherwise
   `stale_snapshot` (`route_changed`);
5. the ref exists in it — otherwise `unknown_ref`;
6. the node is attached, on screen, and enabled — otherwise
   `node_not_actionable` with the reason;
7. the node exposes the action — otherwise `unsupported_action`;
8. `ui_set_text` refuses sensitive (obscured) fields — `node_sensitive`.

Validation runs again **inside** the interaction queue, because the tree can
change while a call waits its turn. That re-check includes consent: the runtime
passes each call a live grant probe bound to its authorization epoch, and the
queue consults it immediately before dispatch. A click that waited while the
user revoked `ui:interact`, or while the runtime stopped, is refused with
`permission_denied` (`authorization_changed`) — the first call already in
flight is allowed to finish, and the second never runs.

A successful call means *dispatched*, not *finished*. It consumes the snapshot,
so the next interaction needs a fresh `ui_get_tree` — which is also how a client
learns what its action did.

## Business actions and capture

**Business actions** are declared by the app, not discovered by the client. Each
`ReleaseAppAction` carries a name (`pay.invoice`), a description, an argument
schema, and a handler; its permission is `app:<name>`, so consent is granted per
action rather than "the agent may do business things". Since PR-09 the schema is
compiled **at registration** (a broken schema fails where the action is declared)
and every call is validated before the handler runs: missing/extra fields, wrong
types, enum and length bounds are refused with `invalid_argument` and a list of
failing field paths — never the offending value. Calls are also size-capped and
serialized with each other.

**Capture** is the one tool whose output cannot be redacted after the fact. So
it is guarded four ways:

1. `ui:capture` consent (never implied by `ui:read` or `ui:interact`);
2. a **deny-by-default** route policy: `ReleaseCapturePolicy()` captures
   nothing; the app must list `allowedRoutes`, and `blockedRoutes` always wins;
3. the route is re-read **after** the frame, and a navigation during capture
   discards the bytes (`route_changed`) rather than returning the wrong screen;
4. a byte budget (an encoded PNG of a phone screen is megabytes; an oversized
   frame is refused, not truncated).

Only PNG is produced in v1 — the reused toolkit path encodes PNG; JPEG is
refused as `unsupported_format` rather than quietly returning PNG.

## Embedded WebView (v0.7.0, optional package)

A WebView's DOM is not a Flutter subtree: `WebViewWidget` hosts a platform view,
so the semantics walk cannot list its `button`/`input`/`table`. The optional
package adds a separate, explicit registry — an agent sees a WebView only
because the app registered it with an origin allow-list:

```dart
final registry = ReleaseWebViewRegistry()
  ..register(
    viewId: 'order-h5',
    engine: WebViewFlutterEngine(controller),
    allowedOrigins: const <String>{'https://app.example.com'},
    privacyPolicy: const ReleaseWebPrivacyPolicy(
      deniedPathPrefixes: <String>{'/account'},
    ),
  );

final tools = ReleaseToolbox(<ReleaseToolSurface>[
  // ... Flutter tools ...
  ReleaseWebTools(source: WebViewDomReleaseSource(registry)),
]);
```

The surface is `web_list_views`, `web_get_tree`, `web_find_element`,
`web_get_state` (`web:read`), and `web_click`, `web_set_text`,
`web_scroll` (`web:interact`). There is deliberately **no** generic
`web_evaluate_javascript`: only fixed scripts with schema-validated parameters
run, and they never return cookies, storage, headers, or raw HTML. Refs are
snapshot-scoped and tied to a navigation epoch; a ref from the previous page is
refused. See [`webview.md`](webview.md).

Platform limits are documented, not hidden: Canvas/WebGL content has no DOM to
read, cross-origin iframes stay opaque, `.click()` is not a trusted user
gesture, and `RenderView` capture does not guarantee platform-view pixels.

## Reuse, not a second implementation

The UI tree comes from `mcp_toolkit`'s `SemanticSnapshotService`: one walk, one
ref vocabulary, so a ref means the same thing in a release build as in a debug
one. The release runtime adds exactly four things on top:

1. **Budgets** — `maxNodes` / `maxDepth` clamped in the runtime *and pushed into
   the snapshot walk*, so a client cannot ask for a tree large enough to stall
   the UI isolate.
2. **Privacy policy** — per-route and per-node rules, full-field masking, and a
   refusal path that builds no payload at all.
3. **A permission boundary with live consent** — every tool declares the
   permission it needs; the runtime refuses a call whose permission the session
   does not hold, and re-checks queued work against the epoch it started in.
4. **A concurrency budget** — at most `maxConcurrentRequests` calls are
   dispatched at once (plus a bounded wait queue); beyond that the answer is
   `server_busy`, not unbounded buffering.

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
- **Consent is explicit and revocable.** Read is structural; interaction,
  capture, app actions, and WebView access need grants, and queued work is
  re-checked against the live grant set.
- **Authentication is not optional.** Loopback is not a trust boundary: other
  apps on the device can reach `127.0.0.1`.
- **Secure by default.** Loopback bind, read-only session, denial-by-default
  privacy/capture policies, nothing bound on construction, no wildcard CORS, no
  fallback ports, stable error codes.
- **No debug capabilities in release.** Eval, hot reload, arbitrary file IO, and
  shell access are out of scope permanently.

## Files

- [`api.md`](api.md) — the public API surface as implemented today.
- [`security.md`](security.md) — what is enforced, what is not, and the limits.
- [`webview.md`](webview.md) — WebView registration, tools, and limits.
- [`security_review_and_webview_plan.md`](security_review_and_webview_plan.md) —
  the 2026-11-04 review findings and their fix status.
- [`upstream-sync.md`](upstream-sync.md) — how this fork tracks upstream
  `main`.
- [`android-deploy.md`](android-deploy.md) — manifest permissions, `adb
  forward`, device matrix.
