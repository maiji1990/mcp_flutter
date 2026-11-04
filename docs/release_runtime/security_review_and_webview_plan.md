# 2026-11-04 security review — fix status

Source review: `mcp_flutter_release_security_webview_review_2026-11-04.md`
(baseline `3d9234b`). This page maps every finding to its implementation and
its evidence. It replaces the "review only" state: the fixes below are in this
branch, but they are **not** a claim of device-verified production safety.

Legend: **fixed** = code + regression test; **partial** = the named part is
fixed and the remainder is documented; **open** = tracked, not implemented.

| ID | Priority | Status | Fix | Evidence |
|---|---|---|---|---|
| SEC-01 | P0 | **fixed** | `ReleaseUiPrivacyPolicy` (denied/masked routes, denied identifiers/types), full-field masking, `AgentSensitive` / `ExcludeFromAgent` | `read_tools_test.dart` (denied route, masked label, subtree removal), `flutter_ui_snapshot_source_test.dart` (wrappers) |
| AUTH-01 | P0 | **fixed** | Authorization epoch on grant/revoke/stop/start; live grant probe carried per call; interaction and action queues re-check immediately before dispatch; `stopping` refuses new work | `interaction_tools_test.dart` (queued click revoked), `app_action_tools_test.dart` (queued action revoked) |
| ACT-01 | P0 | **fixed** | `json_schema` compiled at registration; strict call-time validation (types, required, additionalProperties, bounds, nesting); size budget; sanitized failure paths | `app_action_tools_test.dart` (missing/extra/wrong type/long/out of range, invalid schema, handler not called) |
| CAP-01 | P0 | **fixed** | `allowedRoutes` allow-list, empty by default; `allowWhenRouteUnknown: false`; blocked list wins | `capture_tools_test.dart` (default deny, unknown route, blocked route) |
| CAP-02 | P1 | **fixed** | Route re-read after the frame; navigation during capture discards bytes as `route_changed` | `capture_tools_test.dart` (route change discards frame) |
| UI-01 | P1 | **partial** | Snapshot currency + app snapshot id + route-at-capture re-checked before dispatch; stale reasons `app_moved_on` / `route_changed`; WebView navigation epochs | `interaction_tools_test.dart` (route change), `webview_dom_source_test.dart` (epoch) |
| AUTH-02 | P1 | **open (blocked by SDK)** | `mcp_server` 3.1.1's `ToolHandler` receives only the argument map, so a tool call carries no session id; grants/snapshots stay runtime-global. Device probe shows two sessions acting under one grant | `tool/mcp_multiclient.dart`, extended evidence |
| UI-02 | P1 | **partial** | `maxNodes` is now pushed into `captureSnapshot`; `ui_find_element` passes the ceiling; WebView walks are bounded at the script | `read_tools_test.dart` (budget forwarded) |
| LIFE-01 | P1 | **partial** | Demo stops the runtime when the app leaves the foreground (`WidgetsBindingObserver`); package has no lifecycle controller | demo widget test; no device test |
| NET-01 | P1 | **fixed** | Guarded surface enforces `maxConcurrentRequests` with a bounded (16) wait queue; overflow is `server_busy` | runtime concurrency test |
| CI-01 | P1 | **fixed** | `.github/workflows/release_runtime.yml`: analyze + test all three packages + demo, then a release APK build | workflow file |
| DOC-01 | P2 | **fixed** | README/security/API/WebView docs rewritten against v0.7.0; stale "not started"/"capture unimplemented" text removed | this docs set |
| META-01 | P2 | **fixed** | Both package pubspecs point `repository`/`issue_tracker` at `maiji1990/mcp_flutter`; MIT and upstream attribution kept | pubspecs |
| TEST-01 | P2 | **noted** | Token display stays demo-only; docs say production should use pairing + short-lived tokens and warn about screen recording | `security.md` |

## Deliberate behaviour changes

- `ReleaseCapturePolicy()` now captures nothing. Existing callers must list
  `allowedRoutes` (the demo does).
- A `sensitive` node loses its label and hint too, so tests that expected the
  label to survive were updated.
- `ReleaseToolSurface.call` gained an optional `authorization` parameter;
  `ReleaseUiInteractionDriver` gained `currentRouteName()`.
- `ui_get_tree` forwards `maxNodes` to the source, so `totalNodeCount` is the
  source's count, not the pre-cap runtime count.

## Residual risk (not closed by this work)

1. **Cross-session isolation** — two clients share one grant set and one current
   snapshot. This is the largest remaining design gap.
2. **Token persistence** — in-memory only; no Keystore store yet.
3. **Device matrix** — the v0.7.0 foreground flow is now verified on a Huawei
   PTP-AN10 / Android 17 (2026-11-04), but background, rotation, split screen,
   process death, and multiple clients are not.
4. **Hybrid capture** — WebView pixels under `RenderView` capture are unverified.
5. **WebView device proof** — DOM read/act, SPA History, sandboxed cross-origin
   iframe, controlled input, and hybrid capture are device-verified; a real
   remote-origin iframe and multi-view registration are not.
6. **Keystore persistence** — not implemented; every enable generates a new
   secret, so process death also rotates the token.
7. **Split-screen serving** — the foreground-only controller stops the runtime
   when the activity pauses, which is safe but means split screen is not a
   supported deployment.
