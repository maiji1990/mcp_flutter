// packages/release_runtime/lib/src/runtime_version.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

/// Version reported as `serverInfo.version` during the MCP `initialize`
/// handshake.
///
/// Kept in one place so the pubspec version, the handshake, and the docs cannot
/// disagree. Bump it with `packages/release_runtime/pubspec.yaml`.
const String kReleaseRuntimeVersion = '0.3.0';
