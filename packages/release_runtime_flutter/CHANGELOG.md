## 0.5.0 — unreleased (fork)

### Added

- `FlutterReleaseUiCaptureSource`: reuses `ScreenshotService` for the frame and
  adds measurement plus resampling to the requested scale; reports the route so
  the runtime's policy decides.
- Widget tests: PNG capture through the tool, base64 round trip, and a blocked
  route refused before any frame is taken (capture runs in `runAsync`, because
  rasterising is real engine work rather than fake-async work).

## 0.4.0 — unreleased (fork)

### Added

- `FlutterReleaseUiInteractionDriver`: reuse of `mcp_toolkit`'s
  `GestureInteractionService` (`tapAtRef`, `enterTextAtRef`, `scroll`), with
  liveness/visibility/enabled inspection and driver-error translation.
- Widget tests: a click through `ui_click` increments app state, `ui_set_text`
  writes into a field and reads back, an obscured field is refused, and
  `ui_scroll` moves a list through its scroll action.

## 0.3.0 — unreleased (fork)

## 0.3.0 — unreleased (fork)

### Added

- `FlutterReleaseUiSnapshotSource`: `ReleaseUiSnapshotSource` backed by
  `mcp_toolkit`'s `SemanticSnapshotService`, so release and debug snapshots
  share one walk and one ref vocabulary.
- `sensitive` flagging from `SemanticsFlag.isObscured` (passwords, OTPs).
- Route names from a pluggable `ReleaseRouteProvider`.
- Widget tests covering tree capture, redaction, and find-by-label against a
  real pumped app.