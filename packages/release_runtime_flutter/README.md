# flutter_mcp_toolkit_release_flutter

Flutter adapter for [`flutter_mcp_toolkit_release`](../release_runtime):
it feeds the release runtime's `ui_*` tools from the live semantics tree of a
running app.

```dart
final runtime = ReleaseMcpRuntime.http(
  config: const ReleaseMcpConfig(),
  tools: ReleaseReadTools(
    source: FlutterReleaseUiSnapshotSource(
      routeProvider: CallbackReleaseRouteProvider(() async => myRouter.currentPath),
    ),
  ),
);

await runtime.start(); // only when the user enables local AI access
```

## Acting on the UI

```dart
final store = ReleaseSnapshotStore();
final tools = ReleaseToolbox(<ReleaseToolSurface>[
  ReleaseReadTools(source: FlutterReleaseUiSnapshotSource(), store: store),
  ReleaseInteractionTools(
    store: store,
    driver: const FlutterReleaseUiInteractionDriver(),
  ),
]);
```

`FlutterReleaseUiInteractionDriver` reuses the toolkit's gesture service, so
tap/text/scroll behave the same way they do for the debug tools: a semantic
action when one exists, synthesised pointer events otherwise, and a structured
refusal when the node left the tree. What the driver does not decide is whether
a call may happen at all — permission, snapshot currency, and consumption live
in the core runtime.

## What it adds

| Concern | Where |
|---|---|
| Semantic tree walk | Reused: `mcp_toolkit`'s `SemanticSnapshotService` — one implementation, same ref vocabulary as the debug tools |
| Password-like nodes | Marked `sensitive` from `SemanticsFlag.isObscured`; the runtime's privacy filter masks their text |
| Route name | Whatever you pass as a `ReleaseRouteProvider` (go_router, Router, Navigator, custom) — the package never guesses |
| Current page | `peekSemanticSnapshot`, which does not advance the snapshot id, so asking "what page is this" cannot invalidate refs a client holds |

## Limits

- Runs on the UI isolate. `SemanticsNode` objects never cross an isolate
  boundary; this adapter only produces plain maps and value objects.
- Obscured detection covers `TextField(obscureText: true)` and anything else
  that sets `SemanticsFlag.isObscured`. A custom widget that renders a secret
  without that flag is invisible to it — mark it in the app, or use
  `RedactingPrivacyFilter(maskAllValues: true)` for a blanket policy.
- Tests run under `flutter_test`; release-device verification is tracked as
  PR-06 of the fork plan.