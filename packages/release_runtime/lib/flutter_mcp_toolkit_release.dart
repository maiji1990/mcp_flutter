// flutter_mcp_toolkit_release — opt-in MCP runtime for shipped Flutter apps.
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime). Pure Dart in this PR: no Flutter SDK
// dependency, no dart:io, no socket code, no MCP SDK dependency.

export 'src/config/release_mcp_config.dart';
export 'src/errors/release_mcp_error.dart';
export 'src/lifecycle/runtime_lifecycle.dart';
export 'src/lifecycle/runtime_status.dart';
export 'src/release_runtime.dart';
export 'src/security/permissions.dart';
export 'src/transport/runtime_transport.dart';
