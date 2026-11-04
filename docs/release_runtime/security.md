# Release runtime security model

Status: v0.7.0. The controls below are implemented, covered by tests
(`dart test` 179, `flutter test` 13 for the Flutter adapter, `flutter test`
28 for the WebView package), and the foreground flows were re-run on a real
Android device on 2026-11-04 (see [Verified](#verified)). The gaps listed at the
end — background/rotation lifecycles, multi-client isolation, hybrid capture,
and SPA/iframe behaviour — are still open.

## Transport and session

| Control | Implementation |
|---|---|
| Off by default | Construction binds nothing; `start()` is an explicit call. |
| Loopback-only | `ReleaseMcpConfig.validate()` rejects non-loopback hosts unless `allowNonLoopbackBinding` is set. |
| Bearer auth on every request | `HttpReleaseRuntimeTransport` passes `authToken` to the SDK transport, which answers 401 before dispatch. Loopback is *not* a trust boundary. |
| Constant-time comparison | SDK `_validateBearerToken` + `ReleaseAccessToken.matches`; no byte-by-byte early exit. |
| Token handling | 256 bits from `Random.secure()`; header-only (never a query string); `toString()` redacted; excluded from `status`/`config`/`details` JSON. |
| Token rotation | `rotateAccessToken()` while stopped; the old token is refused after restart (tested). |
| Origin validation | SDK loopback allow-list, `allowAnyOrigin: false`; foreign `Origin` → 403 (tested). |
| No wildcard CORS | `CorsConfig(allowOrigin: 'http://<host>')`. |
| No silent rebinding | `fallbackPorts: const []`; a taken port is a failed start (tested). |
| Request bounds | Body ceiling, per-request timeout, max sessions and idle timeout from config; SDK enforces. |
| Concurrency budget | The guarded surface dispatches at most `maxConcurrentRequests` calls at once and queues at most 16 more; beyond that the answer is `server_busy` (tested). The budget is shared by sessions, which is one reason AUTH-02 is still open. |
| Rate limiting | Optional `ReleaseRateLimit` sliding window (default off; the demo sets 120/minute). Over-budget calls answer `rate_limited` before dispatch. The window is process-global because the SDK exposes no session id (tested). |
| Audit log | Optional `ReleaseAuditSink` receives one record per decision: tool, permission, allowed, reason, argument **keys**, authorization epoch. Sink exceptions are swallowed so auditing cannot break a call; values are never recorded (tested). |

## Tool and consent boundary

| Control | Implementation |
|---|---|
| Per-tool permission gate | Every `ReleaseToolDefinition` names a permission; the runtime refuses a call the session does not hold, before the handler runs (tested both ways). |
| Read-only by default | Only `ui:read` is granted implicitly; interaction, capture, app actions, and WebView access need consent. |
| No silent downgrade | `readOnlyByDefault: false` + missing authorization → `authorization_missing`. |
| Authorization epoch | `start`, `grantPermissions`, `revokePermissions`, `stop`, and `dispose` bump a counter. Each call carries a live grant probe bound to the epoch it started in. |
| Queued-work re-check | Interaction and action queues consult the probe **immediately before dispatch**. A click/action that waited while consent was withdrawn, the runtime stopped, or a new consent round began is refused with `permission_denied` / `authorization_changed`. The in-flight call is allowed to finish; nothing is retroactively cancelled mid-Dart-callback. |
| Stop refuses new work | `stop()` moves to `stopping` before the transport closes, so new calls are `runtime_not_running`; queued calls fail their probe when they reach the front. |
| No secret leakage in errors | Messages are fixed per code; details carry field names, counts, refs, and error *types* only. A throwing handler becomes `unknown_error` without a stack trace or message text (tested). |

## UI privacy (SEC-01)

| Control | Implementation |
|---|---|
| Full-field masking | `RedactingPrivacyFilter` masks `label`, `value`, and `hint` on every `sensitive` node — not only the value. A custom widget that puts the secret in its label no longer leaks it. |
| Page-level read policy | `ReleaseUiPrivacyPolicy.deniedRoutes` refuses `ui_get_tree` and `ui_find_element` with `route_denied`; the refusal is produced before any node is serialized. `maskedRoutes` keeps the tree but masks every field. |
| Node-level policy | `deniedIdentifiers` / `deniedTypes` remove a node and its subtree; `maskedIdentifiers` mask text but keep the ref addressable. Removal is computed in a first pass, so a child listed before its denied parent cannot slip through. |
| Widget-level intent | `AgentSensitive` sets `Semantics.obscured` (the same flag as `TextField(obscureText: true)`); `ExcludeFromAgent` removes the subtree from semantics entirely. Both are tested in a widget test. |
| Denied routes cannot be bypassed by `ui:read` | The route decision happens in the filter, after the permission gate, so a granted session still cannot read a denied page. |
| No text in refusals | A `route_denied` result contains a reason token, never the screen's content (tested with `4111 1111 1111 1111`). |

### Privacy limits (documented, not hidden)

- **Nothing is automatic.** Semantics has no "this is a secret" bit. A screen
  that shows secrets and is not declared in the policy (and whose widgets are not
  wrapped) still leaks. The policy is the contract; the demo declares
  `/wallet` and wraps the card text as a second layer.
- **Unknown route.** `denyWhenRouteUnknown` defaults to false so apps without a
  router keep a read surface. An app that declares denied routes should set it
  to true: "unknown" then means "cannot prove this is safe".
- **Screenshots are separate.** Pixels cannot be redacted by a JSON filter;
  capture has its own deny-by-default policy below.
- **Platform views.** `RenderView` capture does not guarantee Android platform
  view pixels (WebView included). `ui_capture` may therefore show a hole where a
  WebView is; it must not be described as a complete screenshot. Hybrid capture
  is not implemented.

## Capture (CAP-01 / CAP-02)

| Control | Implementation |
|---|---|
| Deny by default | `ReleaseCapturePolicy()` has an empty `allowedRoutes`; capture is refused (`route_blocked`) until the app lists what is safe. `blockedRoutes` always wins. |
| Unknown route refused | `allowWhenRouteUnknown` defaults to false. |
| Pre-frame check | The route is read **before** the frame; a blocked route never reaches the capture source. |
| Post-frame check | The route is read again after the frame. A navigation during capture discards the image and answers `route_changed`; no `bytesBase64` is produced (tested). |
| Consent re-check | `ui:capture` is checked again immediately before the source is asked, so a revocation cannot race a slow frame. |
| Size budget | Oversized frames are refused (`capture_too_large`) rather than truncated. |
| Format | PNG only; JPEG answers `unsupported_format` instead of silently returning PNG. |

## App actions (ACT-01)

| Control | Implementation |
|---|---|
| Schema at registration | `ReleaseAppAction` compiles its JSON Schema in the constructor; an unusable schema throws `ArgumentError` where the action is declared. Compilation is synchronous and never fetches a remote `$ref`. |
| Schema at call time | Every call is validated before the handler runs: type, required/extra properties (`additionalProperties: false`), enums, numeric bounds, string lengths, nested objects/arrays. Failure is `invalid_argument` with field paths only. |
| Size budget | `arguments` over `maxArgumentBytes` (64 KiB default) is refused before validation. |
| Business authorization | Validation is a shape check, not authorization: the handler still owns the app's business rules; high-risk actions should require confirmation, server-side checks, and an idempotency key inside the handler. |
| Serialized | Actions run one at a time and re-check their `app:<name>` grant at dispatch. |

## Interaction consistency (UI-01)

- Refs are snapshot-scoped; a snapshot is consumed after a successful action.
- Before dispatch the runtime re-checks: snapshot currency, the app's snapshot id,
  and the **route** the snapshot was taken on. A user who navigated after the read
  gets `stale_snapshot` / `route_changed`, not a click on whatever took the
  node's place.
- Node state (attached, visible, enabled) is re-inspected at dispatch; capability
  comes from the snapshot metadata, not the live action set (Flutter only
  publishes `setText` after focus).
- What is *not* proved: a widget can rebuild in place without changing the
  snapshot counter or route. A true UI fingerprint (widget identity + geometry +
  semantic epoch) is still future work; PR-10 covers the route and snapshot id,
  not every rebuild.

## WebView boundary (v0.7.0)

| Control | Implementation |
|---|---|
| Explicit registration | `ReleaseWebViewRegistry` is the only way a view exists; there is no widget-tree scan. `viewId` and an origin allow-list are required. |
| Origin allow-list | Exact `scheme://host[:port]` matching. HTTPS only by default; `allowHttp` is an explicit staging opt-in. Pages outside the list are refused before a script runs. |
| No arbitrary JavaScript | The MCP surface has no `web_evaluate_javascript`. Only fixed adapter scripts with schema-validated parameters run; there is no cookie/storage/HTML accessor. |
| DOM privacy | Password fields, `data-agent-sensitive`, payment/OTP autocomplete values, and secret-looking names are redacted in the page script and masked again in Dart. `ReleaseWebPrivacyPolicy` denies path prefixes and non-web URLs. |
| Ref scope | A ref is opaque, snapshot-scoped, and only valid while the page-global nonce matches. The element must still be the same tag and role, or the action is refused. Navigating (including SPA History changes) advances the navigation epoch; the previous snapshot id is refused. |
| Bounded work | Node, depth, text, and result-size budgets; per-script timeout; only interactive elements are walked. |
| No native bridge | No `addJavascriptInterface`/`JavaScriptChannel`; the app calls `runJavaScriptReturningResult` with fixed scripts. |
| Separate consent | `web:read` and `web:interact` are independent of `ui:read`/`ui:interact`. |

### WebView limits

- DOM text is untrusted content: it is returned as data, never as instructions
  or authorization. Prompt-injection handling belongs to the client.
- `.click()` and script-injected input are not trusted user gestures; sites can
  refuse them, and logins/payments should stay human or app-API driven.
- Canvas/WebGL, video, and cross-origin iframes have no readable DOM; they are
  not silently approximated.
- DOM rectangles are CSS pixels in the page viewport; cross-layer coordinate
  clicks need host offset, scroll, and DPR math and are not implemented (actions
  are DOM-based on purpose).

## Verified

Unit/widget tests cover every control above, including the negative cases
(denied route, masked label, queued revocation, schema rejection, navigation
during capture, stale WebView ref).

### v0.7.0 device run — 2026-11-04

Release APK (18.4 MB, Flutter 3.47.9 / Dart 3.13.7) installed on a **Huawei
PTP-AN10 (PTP_AN10), Android 17 (API 37), arm64**. The fixture was driven from
the computer over `adb forward` with
`tool/mcp_smoke.dart --webview-check --wallet-check`; every step passed.

- `initialize` reports `flutter_mcp_toolkit_release 0.7.0`; `tools/list`
  returns the 8 Flutter tools and the 7 `web_*` tools.
- Flutter: `ui_get_tree`, `ui_click` (counter changed), `ui_set_text`
  (value read back), `ui_scroll`, `ui_capture` (512x1120 PNG).
- ACT-01: `app_invoke_action` with an extra argument is `invalid_argument`;
  the valid call runs.
- SEC-01/CAP: on `/wallet`, `ui_get_tree` is `route_denied` with the card
  number absent from the payload, and `ui_capture` is `route_blocked` with no
  `bytesBase64`.
- WebView (W02/W03): a locally served H5 page in a real `WebViewWidget`
  (loopback origin, exact allow-list) was registered as `order-h5`,
  `web_get_tree` returned its 3 interactive nodes with the PIN masked,
  `web_set_text` filled the search box, `web_click` ran the page button,
  a fresh `web_get_tree` saw `Result for INV-42`, replaying the consumed
  snapshot was `stale_snapshot`, and `ui_capture` on `/web-demo` was
  `route_blocked`.
- `web_get_state` reported the sanitized loopback origin and navigation epoch.
- WebView edge cases: a SPA `pushState` advanced the epoch to 2, re-sampled the
  new page, and refused the pre-navigation snapshot; a sandboxed cross-origin
  iframe rendered in the hybrid PNG while its button stayed out of
  `web_get_tree`; a framework-style controlled input re-rendered from state
  (`Model: hello frame`).
- Hybrid capture: `ui_capture` on the WebView screen produced a 640x1400 PNG
  whose pixels include the H5 content (visually verified). `RenderView` does
  composite the platform view on this device; that is not a general guarantee.
- Lifecycle: HOME/background and the lock screen both stopped the endpoint
  (`Status: paused (app in background)`); rotation landscape↔portrait kept it
  healthy; re-enabling produced a new token and the old one answered 401.
- Multi-client: two concurrent sessions both read and both invoked the demo
  action under one grant — direct evidence that AUTH-02 isolation is still
  open (the SDK handler receives no session id).
- Rate limiting: 5 calls passed; 130 calls in the same minute gave 115 OK and
  15 `rate_limited` against the demo's 120/minute budget.
- Audit: `adb logcat` showed one record per call with tool, permission,
  decision, and epoch — no argument values.
- Process death: force-stop made the endpoint unreachable and a relaunch came
  up with `Status: off`.
- Split/freeform: the windowing transition paused the activity, so the
  foreground-only controller stopped the endpoint. Split-screen serving is not
  supported by design; a true two-app split was not exercised.

Full transcripts (token redacted):
[`evidence/2026-11-04-device-smoke.txt`](evidence/2026-11-04-device-smoke.txt),
[`evidence/2026-11-04-device-extended.txt`](evidence/2026-11-04-device-extended.txt).

Two defects surfaced only on hardware and were fixed before the final run:

1. Android's `evaluateJavascript` returns the **double-encoded** JSON text of
   a script's string result; the adapter now unwraps strings until a map
   appears (unit-tested).
2. The Dart escape `\s` in the generated page script collapsed to `s`,
   so the whitespace normalizer mangled labels ("Search orders" → "Search
   order"); the script now emits `\s` and a script test pins it.

### Earlier device evidence (PR-06, v0.6.0)

Release APK on the same device class: `ui_get_tree`, `ui_click`,
`ui_set_text`, `ui_scroll`, `app_invoke_action`, `ui_capture`, and
`route_blocked` on `/wallet`. This predates the v0.7.0 controls and is kept
only as history.

## Still required before a production release

- **Session isolation (AUTH-02).** Grants and the snapshot store are
  runtime-global: two clients share one consent set and one "current snapshot".
  A per-session grant/snapshot scope, device pairing, and per-session quotas are
  designed but not implemented.
- **Keystore-backed token storage.** The token lives in memory. Persisting it
  needs an Android Keystore-backed store; `SharedPreferences` would put the
  secret in app-readable storage.
- **Revocation UX semantics.** Rotation is stop → rotate → start; a "revoke
  access" action should also drop any persisted token and stop the runtime.
- **Keystore-backed persistence.** The token is still memory-only; every
  re-enable generates a new secret. Persisting it needs an Android
  Keystore-backed store behind `ReleaseAccessToken.restore`, and a revoke
  action that drops it.
- **Per-session rate budgets.** The limiter and audit stream are process-global
  for the same SDK reason as AUTH-02: a tool call carries no session id.
- **Device matrix.** The v0.7.0 foreground flow is verified, but
  background/lock screen, rotation, split screen, process death, multiple
  clients, and any API level below 37 remain unverified. The demo stops the
  runtime when the app leaves the foreground; that path is widget-tested only,
  not exercised on hardware.
- **Hybrid capture.** `ui_capture` on a screen containing a platform view
  (WebView) is not verified; it may be incomplete and must be reported as such.
- **WebView device proof.** The DOM read/act flow is verified on device, but
  SPA History navigation, cross-origin iframes, framework-controlled inputs, and
  hybrid (platform-view) screenshots are not.

## Non-goals (permanent)

Dart expression evaluation, arbitrary JavaScript evaluation, hot reload/restart,
VM introspection, arbitrary file IO, cookie/storage access, and shell execution.
A release build has no legitimate reason to expose them, so they are excluded
from the tool catalog rather than permission-gated.
