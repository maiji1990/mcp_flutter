// flutter_mcp_toolkit_release — opt-in MCP runtime for shipped Flutter apps.
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime). Ships a loopback Streamable HTTP MCP
// endpoint backed by the published `mcp_server` package; it carries no VM
// Service, no service extensions, and no Dart eval.

export 'src/config/release_mcp_config.dart';
export 'src/errors/release_mcp_error.dart';
export 'src/lifecycle/runtime_lifecycle.dart';
export 'src/lifecycle/runtime_status.dart';
export 'src/release_runtime.dart';
export 'src/runtime_version.dart';
export 'src/security/access_token.dart';
export 'src/security/permissions.dart';
export 'src/server/http_transport.dart';
export 'src/transport/runtime_transport.dart';
