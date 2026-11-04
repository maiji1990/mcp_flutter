// packages/release_runtime_webview/lib/src/dom_snapshot_script.dart
// Copyright (c) 2025, Flutter Inspector MCP Server authors.
// Licensed under the MIT License.
//
// Fork addition (Android release runtime, v0.7.0).
//
// Fixed scripts only. The parameters below are bounded primitives; no caller
// string ever becomes JavaScript code.

import 'dart:convert';

/// Builds the DOM snapshot script.
///
/// The script:
/// - refuses any page whose `location.origin` is not in [allowedOrigins];
/// - walks only interactive elements (`button`, `a`, `input`, ...), within a
///   node and depth budget, so a huge page cannot stall the WebView;
/// - marks password / payment / one-time-code fields and redacts their text
///   before returning;
/// - stores the element behind each ref in a page-global map, keyed by
///   [nonce], so an action can prove the ref belongs to the snapshot it claims;
/// - never returns cookies, storage, headers, or raw HTML.
String buildDomSnapshotScript({
  required Iterable<String> allowedOrigins,
  required int maxNodes,
  required int maxDepth,
  required String nonce,
  int maxTextLength = 200,
}) {
  final origins = jsonEncode(allowedOrigins.toList(growable: false));
  final nonceLiteral = jsonEncode(nonce);
  return '''
(() => {
  try {
    var ORIGINS = $origins;
    var MAX_NODES = $maxNodes;
    var MAX_DEPTH = $maxDepth;
    var MAX_TEXT = $maxTextLength;
    var NONCE = $nonceLiteral;
    if (ORIGINS.indexOf(location.origin) === -1) {
      return JSON.stringify({ error: 'origin_denied' });
    }
    var SELECTOR = 'button,a,input,textarea,select,summary,[role],[tabindex],[contenteditable]';
    var SECRET_NAME = /card|ssn|otp|passcode|seed|secret|token|cvv|cvc|iban|account/i;
    var SECRET_AUTOCOMPLETE = /cc-|one-time-code|current-password|new-password/;
    var clean = function (value, limit) {
      return String(value || '').replace(/\\s+/g, ' ').trim().slice(0, limit);
    };
    var depthOf = function (el) {
      var depth = 0;
      var current = el;
      while (current && current !== document.body) {
        current = current.parentElement;
        depth += 1;
        if (depth > MAX_DEPTH) { return depth; }
      }
      return depth;
    };
    var visible = function (el) {
      var rect = el.getBoundingClientRect();
      if (rect.width <= 0 || rect.height <= 0) { return false; }
      if (el.getClientRects().length === 0) { return false; }
      var style = getComputedStyle(el);
      if (style.display === 'none' || style.visibility === 'hidden' || style.visibility === 'collapse') { return false; }
      if (style.opacity === '0') { return false; }
      if (el.getAttribute('aria-hidden') === 'true') { return false; }
      return true;
    };
    var elements = Array.prototype.slice.call(document.querySelectorAll(SELECTOR));
    var store = globalThis.__flutterReleaseMcpV1 || {};
    store.refs = new Map();
    store.nonce = NONCE;
    store.href = location.href;
    globalThis.__flutterReleaseMcpV1 = store;
    var nodes = [];
    var truncated = false;
    for (var index = 0; index < elements.length; index += 1) {
      if (nodes.length >= MAX_NODES) { truncated = true; break; }
      var el = elements[index];
      if (depthOf(el) > MAX_DEPTH) { continue; }
      if (!visible(el)) { continue; }
      var tag = el.tagName.toLowerCase();
      var type = (el.getAttribute('type') || '').toLowerCase();
      var autocomplete = (el.getAttribute('autocomplete') || '').toLowerCase();
      var isForm = tag === 'input' || tag === 'textarea' || tag === 'select';
      var secret = type === 'password'
        || el.hasAttribute('data-agent-sensitive')
        || SECRET_AUTOCOMPLETE.test(autocomplete)
        || SECRET_NAME.test(String(el.name || '') + ' ' + String(el.id || ''));
      var ref = 'w' + NONCE + '_' + nodes.length;
      store.refs.set(ref, {
        el: el,
        tag: tag,
        role: el.getAttribute('role') || ''
      });
      var label = el.getAttribute('aria-label') || '';
      if (!label && el.labels && el.labels.length > 0) {
        label = el.labels[0].textContent || '';
      }
      if (!label && el.getAttribute('title')) {
        label = el.getAttribute('title');
      }
      var text = isForm ? '' : (el.innerText || '');
      var value = isForm ? String(el.value || '') : '';
      var rect = el.getBoundingClientRect();
      nodes.push({
        ref: ref,
        tag: tag,
        role: el.getAttribute('role') || '',
        type: type,
        label: secret ? '[REDACTED]' : clean(label, MAX_TEXT),
        text: secret ? '[REDACTED]' : clean(text, MAX_TEXT),
        value: secret ? '[REDACTED]' : clean(value, MAX_TEXT),
        placeholder: secret ? '[REDACTED]' : clean(el.getAttribute('placeholder'), MAX_TEXT),
        disabled: Boolean(el.disabled) || el.getAttribute('aria-disabled') === 'true',
        checked: typeof el.checked === 'boolean' ? el.checked : null,
        sensitive: secret,
        rect: { x: rect.left, y: rect.top, width: rect.width, height: rect.height }
      });
    }
    return JSON.stringify({
      origin: location.origin,
      href: location.href,
      title: document.title,
      nonce: NONCE,
      truncated: truncated,
      nodes: nodes
    });
  } catch (error) {
    return JSON.stringify({ error: 'script_failed' });
  }
})()
''';
}
