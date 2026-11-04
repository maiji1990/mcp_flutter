// packages/release_runtime/lib/src/privacy/privacy_policy.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime).

import 'package:meta/meta.dart';

import '../ui/release_ui_types.dart';

/// What a policy says about one route or one node.
enum ReleasePrivacyDecision {
  /// Text may be serialized (still subject to length truncation).
  allow('allow'),

  /// The node stays, but every text field is replaced by the mask marker.
  mask('mask'),

  /// The route may not be read, or the node (and its subtree) is removed.
  deny('deny');

  const ReleasePrivacyDecision(this.wireName);

  /// Stable wire name, for logs and error details.
  final String wireName;
}

/// Page- and node-level read policy for the UI tree.
///
/// The privacy filter alone cannot protect a screen whose secrets are ordinary
/// `Text` widgets: nothing in the semantics tree says "this is a card number".
/// The app therefore declares what is sensitive, and the policy decides before
/// a snapshot leaves the device:
///
/// - **Route level** — [deniedRoutes] refuse the snapshot outright, even when
///   the session holds `ui:read`; [maskedRoutes] keep the tree but mask every
///   text field on those pages.
/// - **Node level** — a node flagged `sensitive` (obscured semantics, or the
///   `AgentSensitive` wrapper) always has `label`, `value`, and `hint`
///   masked; [maskedIdentifiers] does the same for an app-chosen identifier and
///   [deniedIdentifiers] removes the node and its descendants entirely.
/// - **Catch-all** — [maskAllValues] masks every value, for apps whose policy is
///   "no field text ever".
///
/// The defaults are safe but not magic: an app that shows secrets on a screen
/// nobody declared is still exposed. Declaring the screen (or wrapping the
/// widget) is the contract; `docs/release_runtime/security.md` says so.
@immutable
final class ReleaseUiPrivacyPolicy {
  const ReleaseUiPrivacyPolicy({
    this.deniedRoutes = const <String>{},
    this.maskedRoutes = const <String>{},
    this.deniedIdentifiers = const <String>{},
    this.maskedIdentifiers = const <String>{},
    this.deniedTypes = const <String>{},
    this.maskAllValues = false,
    this.maskSensitiveLabels = true,
    this.denyWhenRouteUnknown = false,
  });

  /// Routes that may never be read, whatever the session was granted.
  final Set<String> deniedRoutes;

  /// Routes whose nodes keep their structure but lose every text field.
  final Set<String> maskedRoutes;

  /// Identifiers whose node and subtree are removed from the snapshot.
  final Set<String> deniedIdentifiers;

  /// Identifiers whose node text is masked but remains addressable.
  final Set<String> maskedIdentifiers;

  /// Node roles (`textField`, `label`, ...) whose text is masked.
  final Set<String> deniedTypes;

  /// Mask every node's text (`label`, `value`, `hint`), not only the
  /// sensitive ones.
  final bool maskAllValues;

  /// Mask label and hint on sensitive nodes in addition to the value.
  ///
  /// True by default: a password's `label` ("Card number") is harmless, but a
  /// custom widget may put the secret in the label, and masking all three is the
  /// only rule that cannot be talked around.
  final bool maskSensitiveLabels;

  /// What to do when the app cannot name the current route.
  ///
  /// False by default so an app without a router still gets a read surface. An
  /// app that declares denied routes and cannot report its route should set
  /// this to true: "unknown" then means "cannot prove this is not the sensitive
  /// page".
  final bool denyWhenRouteUnknown;

  /// Decision for a snapshot whose route is [routeName].
  ReleasePrivacyDecision routeDecision(String? routeName) {
    final route = _normalizeRoute(routeName);
    if (route == null) {
      return denyWhenRouteUnknown
          ? ReleasePrivacyDecision.deny
          : ReleasePrivacyDecision.allow;
    }
    if (deniedRoutes.contains(route)) {
      return ReleasePrivacyDecision.deny;
    }
    if (maskAllValues || maskedRoutes.contains(route)) {
      return ReleasePrivacyDecision.mask;
    }
    return ReleasePrivacyDecision.allow;
  }

  /// Decision for one node of an allowed route.
  ReleasePrivacyDecision nodeDecision(ReleaseUiNode node) {
    final identifier = node.identifier;
    if (identifier != null && deniedIdentifiers.contains(identifier)) {
      return ReleasePrivacyDecision.deny;
    }
    if (deniedTypes.contains(node.type)) {
      return ReleasePrivacyDecision.deny;
    }
    if (node.sensitive) {
      return ReleasePrivacyDecision.mask;
    }
    if (identifier != null && maskedIdentifiers.contains(identifier)) {
      return ReleasePrivacyDecision.mask;
    }
    if (maskAllValues) {
      return ReleasePrivacyDecision.mask;
    }
    return ReleasePrivacyDecision.allow;
  }

  /// True when the policy declares at least one route-level restriction.
  bool get hasRouteRules =>
      deniedRoutes.isNotEmpty || maskedRoutes.isNotEmpty || maskAllValues;

  /// Copy with additional rules; later rules win at lookup time.
  ReleaseUiPrivacyPolicy merge(ReleaseUiPrivacyPolicy other) =>
      ReleaseUiPrivacyPolicy(
        deniedRoutes: <String>{...deniedRoutes, ...other.deniedRoutes},
        maskedRoutes: <String>{...maskedRoutes, ...other.maskedRoutes},
        deniedIdentifiers: <String>{
          ...deniedIdentifiers,
          ...other.deniedIdentifiers,
        },
        maskedIdentifiers: <String>{
          ...maskedIdentifiers,
          ...other.maskedIdentifiers,
        },
        deniedTypes: <String>{...deniedTypes, ...other.deniedTypes},
        maskAllValues: maskAllValues || other.maskAllValues,
        maskSensitiveLabels: maskSensitiveLabels || other.maskSensitiveLabels,
        denyWhenRouteUnknown:
            denyWhenRouteUnknown || other.denyWhenRouteUnknown,
      );

  static String? _normalizeRoute(String? routeName) {
    if (routeName == null) {
      return null;
    }
    final trimmed = routeName.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
