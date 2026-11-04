// flutter_mcp_toolkit_release — opt-in MCP runtime for shipped Flutter apps.
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime). Ships a loopback Streamable HTTP MCP
// endpoint backed by the published `mcp_server` package; it carries no VM
// Service, no service extensions, and no Dart eval.

export 'src/actions/app_action.dart';
export 'src/actions/app_action_tools.dart';
export 'src/capture/capture_policy.dart';
export 'src/capture/capture_source.dart';
export 'src/config/release_mcp_config.dart';
export 'src/errors/release_mcp_error.dart';
export 'src/lifecycle/runtime_lifecycle.dart';
export 'src/lifecycle/runtime_status.dart';
export 'src/privacy/privacy_filter.dart';
export 'src/privacy/privacy_policy.dart';
export 'src/release_runtime.dart';
export 'src/runtime_version.dart';
export 'src/security/access_token.dart';
export 'src/security/audit.dart';
export 'src/security/call_authorization.dart';
export 'src/security/permissions.dart';
export 'src/security/rate_limiter.dart';
export 'src/server/http_transport.dart';
export 'src/tools/capture_tools.dart';
export 'src/tools/interaction_tools.dart';
export 'src/tools/read_tools.dart';
export 'src/tools/release_tools.dart';
export 'src/tools/snapshot_store.dart';
export 'src/tools/toolbox.dart';
export 'src/transport/runtime_transport.dart';
export 'src/ui/interaction_driver.dart';
export 'src/ui/release_ui_types.dart';
export 'src/ui/route_provider.dart';
export 'src/web/release_web_privacy.dart';
export 'src/web/release_web_source.dart';
export 'src/web/release_web_types.dart';
export 'src/web/web_tools.dart';
