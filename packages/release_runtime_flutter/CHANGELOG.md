## 0.3.0 — unreleased (fork)

### Added

- `FlutterReleaseUiSnapshotSource`: `ReleaseUiSnapshotSource` backed by
  `mcp_toolkit`'s `SemanticSnapshotService`, so release and debug snapshots
  share one walk and one ref vocabulary.
- `sensitive` flagging from `SemanticsFlag.isObscured` (passwords, OTPs).
- Route names from a pluggable `ReleaseRouteProvider`.
- Widget tests covering tree capture, redaction, and find-by-label against a
  real pumped app.
