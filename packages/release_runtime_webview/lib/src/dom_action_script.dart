// packages/release_runtime_webview/lib/src/dom_action_script.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).

import 'dart:convert';

/// Builds the script that clicks the element behind [ref].
///
/// Every action script refuses when:
/// - the page is not on an allowed origin;
/// - the page-global ref map has a different [nonce] (snapshot replaced);
/// - the element is gone, detached, hidden, or disabled.
String buildDomClickScript({
  required Iterable<String> allowedOrigins,
  required String ref,
  required String nonce,
}) => _build(
  kind: 'click',
  allowedOrigins: allowedOrigins,
  ref: ref,
  nonce: nonce,
);

/// Builds the script that replaces the text of the control behind [ref].
///
/// The value is installed through the prototype setter so React/Vue controlled
/// inputs observe the change, then `input` and `change` are dispatched. A
/// password or `data-agent-sensitive` control is refused, not filled.
String buildDomSetTextScript({
  required Iterable<String> allowedOrigins,
  required String ref,
  required String nonce,
  required String text,
}) => _build(
  kind: 'setText',
  allowedOrigins: allowedOrigins,
  ref: ref,
  nonce: nonce,
  text: text,
);

/// Builds the script that scrolls the page or the control behind [ref].
String buildDomScrollScript({
  required Iterable<String> allowedOrigins,
  required String ref,
  required String nonce,
  required String direction,
  required double amount,
}) => _build(
  kind: 'scroll',
  allowedOrigins: allowedOrigins,
  ref: ref,
  nonce: nonce,
  direction: direction,
  amount: amount,
);

String _build({
  required String kind,
  required Iterable<String> allowedOrigins,
  required String ref,
  required String nonce,
  String? text,
  String? direction,
  double? amount,
}) {
  final origins = jsonEncode(allowedOrigins.toList(growable: false));
  final refLiteral = jsonEncode(ref);
  final nonceLiteral = jsonEncode(nonce);
  final textLiteral = jsonEncode(text ?? '');
  final directionLiteral = jsonEncode(direction ?? 'down');
  final amountLiteral = (amount ?? 300).toStringAsFixed(1);
  final body = switch (kind) {
    'setText' =>
      '''
    var secret = (el.getAttribute('type') || '').toLowerCase() === 'password'
      || el.hasAttribute('data-agent-sensitive');
    if (secret) { return JSON.stringify({ error: 'target_sensitive' }); }
    el.focus({ preventScroll: true });
    if (el.isContentEditable) {
      el.textContent = TEXT;
      el.dispatchEvent(new Event('input', { bubbles: true }));
    } else if (el.tagName === 'INPUT' || el.tagName === 'TEXTAREA') {
      var proto = el.tagName === 'TEXTAREA'
        ? HTMLTextAreaElement.prototype
        : HTMLInputElement.prototype;
      var descriptor = Object.getOwnPropertyDescriptor(proto, 'value');
      if (descriptor && descriptor.set) {
        descriptor.set.call(el, TEXT);
      } else {
        el.value = TEXT;
      }
      el.dispatchEvent(new Event('input', { bubbles: true }));
      el.dispatchEvent(new Event('change', { bubbles: true }));
    } else {
      return JSON.stringify({ error: 'not_editable' });
    }
    return JSON.stringify({ ok: true, href: location.href });
''',
    'scroll' =>
      '''
    var scroller = el.closest('[data-agent-scroll]') || document.scrollingElement || document.documentElement;
    var top = 0;
    var left = 0;
    if (DIRECTION === 'down') { top = AMOUNT; }
    if (DIRECTION === 'up') { top = -AMOUNT; }
    if (DIRECTION === 'right') { left = AMOUNT; }
    if (DIRECTION === 'left') { left = -AMOUNT; }
    el.scrollIntoView({ block: 'center', inline: 'nearest' });
    if (scroller && typeof scroller.scrollBy === 'function') {
      scroller.scrollBy({ top: top, left: left, behavior: 'auto' });
    }
    return JSON.stringify({ ok: true, href: location.href });
''',
    _ =>
      '''
    el.scrollIntoView({ block: 'center', inline: 'center' });
    if (typeof el.focus === 'function') { el.focus({ preventScroll: true }); }
    el.click();
    return JSON.stringify({ ok: true, href: location.href });
''',
  };

  return '''
(() => {
  try {
    var ORIGINS = $origins;
    var NONCE = $nonceLiteral;
    var REF = $refLiteral;
    var TEXT = $textLiteral;
    var DIRECTION = $directionLiteral;
    var AMOUNT = $amountLiteral;
    if (ORIGINS.indexOf(location.origin) === -1) {
      return JSON.stringify({ error: 'origin_denied' });
    }
    var store = globalThis.__flutterReleaseMcpV1;
    if (!store || store.nonce !== NONCE || !(store.refs instanceof Map)) {
      return JSON.stringify({ error: 'stale_ref', reason: 'snapshot_replaced' });
    }
    if (store.href && store.href !== location.href) {
      return JSON.stringify({
        error: 'navigation_changed',
        reason: 'page_moved'
      });
    }
    var entry = store.refs.get(REF);
    var el = entry && entry.el;
    if (!el || !el.isConnected) {
      return JSON.stringify({ error: 'stale_ref', reason: 'element_gone' });
    }
    if (entry.tag && el.tagName.toLowerCase() !== entry.tag) {
      return JSON.stringify({ error: 'stale_ref', reason: 'element_replaced' });
    }
    if ((el.getAttribute('role') || '') !== entry.role) {
      return JSON.stringify({ error: 'stale_ref', reason: 'role_changed' });
    }
    var rect = el.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) {
      return JSON.stringify({ error: 'target_hidden' });
    }
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') {
      return JSON.stringify({ error: 'target_disabled' });
    }
$body
  } catch (error) {
    return JSON.stringify({ error: 'script_failed' });
  }
})()
''';
}
