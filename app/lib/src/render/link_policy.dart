/// The Reader's link-tap decision table, extracted as a PURE function so
/// the two engines share ONE policy instead of forking it:
///
/// - The **native** engine's `onLinkTap` consumes [decideLinkTap]
///   directly (reader.dart's `_handleNativeLinkTap`).
/// - The **webview** engine's `NavigationDelegate` keeps its exact
///   pre-v2 code path UNTOUCHED — its extra branches are webview-load
///   quirks, not tap policy: iOS surfaces `loadHtmlString`'s own load as
///   `about:blank` (which the delegate must allow there and only there),
///   and Android never routes API-initiated loads through the delegate
///   at all. A native tap has no API load to disambiguate, so here every
///   `about:*` URL is what it can only be — a tapped link — and
///   declines on every platform.
///
/// `link_policy_test.dart` mirrors the webview suite's decision cases
/// test-for-test, so the two engines cannot drift silently.
///
/// Pure Dart + foundation's [TargetPlatform] only: no widgets, no
/// webview, no platform channels — unit-testable without fakes.
library;

import 'package:flutter/foundation.dart' show TargetPlatform;

/// The verdict for one tapped link URL — a sealed union so consumers
/// switch exhaustively. Value semantics (`==`) so tests compare
/// decisions directly.
sealed class LinkDecision {
  const LinkDecision();
}

/// `http`/`https`: hand [uri] to the OS browser (the Reader's
/// `_openExternal`). Never navigated in-place.
final class LinkExternal extends LinkDecision {
  const LinkExternal(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) => other is LinkExternal && other.uri == uri;

  @override
  int get hashCode => Object.hash(LinkExternal, uri);

  @override
  String toString() => 'LinkExternal($uri)';
}

/// A scheme-less `.md`/`.markdown` target: open in-app, on BOTH
/// platforms (v2 retires the webview-era Android internal-nav no-op).
///
/// [target] is the authored href with any `#fragment`/`?query` suffix
/// stripped, still UNRESOLVED: the consumer routes it through
/// `VaultPath.resolve` against the current entry's directory, which
/// owns rejecting absolute paths and vault-root escapes — the same
/// split of duties the webview path has always had between its
/// delegate and `_openInternalRelative`.
final class LinkInternalMd extends LinkDecision {
  const LinkInternalMd(this.target);

  final String target;

  @override
  bool operator ==(Object other) =>
      other is LinkInternalMd && other.target == target;

  @override
  int get hashCode => Object.hash(LinkInternalMd, target);

  @override
  String toString() => 'LinkInternalMd($target)';
}

/// A pure `#fragment` link (no file target): jump to the heading in
/// THIS document whose `anchorId` matches [fragment], the native
/// equivalent of a browser's in-page anchor jump. [fragment] is the
/// decoded fragment text (no leading `#`), never empty (an empty or
/// absent fragment is a [LinkDecline], not this).
final class LinkFragment extends LinkDecision {
  const LinkFragment(this.fragment);

  final String fragment;

  @override
  bool operator ==(Object other) =>
      other is LinkFragment && other.fragment == fragment;

  @override
  int get hashCode => Object.hash(LinkFragment, fragment);

  @override
  String toString() => 'LinkFragment($fragment)';
}

/// A `mailto:`/`tel:` link (issue #15): the library's URL allowlist
/// permits both, but unlike `http(s)` a tap here leaves the app for the
/// Mail/Phone app with no in-app undo, so the consumer must show a brief
/// confirmation ("Open in Mail/Phone app?") BEFORE handing [uri] to
/// `url_launcher` — never launch straight from this decision the way
/// [LinkExternal] does.
final class LinkConfirmExternal extends LinkDecision {
  const LinkConfirmExternal(this.uri);

  final Uri uri;

  @override
  bool operator ==(Object other) =>
      other is LinkConfirmExternal && other.uri == uri;

  @override
  int get hashCode => Object.hash(LinkConfirmExternal, uri);

  @override
  String toString() => 'LinkConfirmExternal($uri)';
}

/// Everything else is an explicit no-op: `data:`/`file:`/`about:`/unknown
/// schemes, non-Markdown relative targets, a pure `?query` (no
/// fragment), and anything [Uri.tryParse] cannot parse.
final class LinkDecline extends LinkDecision {
  const LinkDecline();

  @override
  bool operator ==(Object other) => other is LinkDecline;

  @override
  int get hashCode => (LinkDecline).hashCode;

  @override
  String toString() => 'LinkDecline()';
}

/// Decides what a tapped link should do. The table, mirroring the
/// webview delegate's tap semantics exactly:
///
/// | URL shape                                   | decision              |
/// |---------------------------------------------|-----------------------|
/// | unparseable                                 | [LinkDecline]         |
/// | `http:`/`https:` (any case — Uri normalizes)| [LinkExternal]        |
/// | `mailto:`/`tel:` (any case)                  | [LinkConfirmExternal] |
/// | scheme-less ending `.md`/`.markdown` (any   | [LinkInternalMd]      |
///   case), after `#`/`?` stripping            |                       |
/// | scheme-less, pure `#fragment` (non-empty)   | [LinkFragment]        |
/// | scheme-less, anything else (non-md target,  | [LinkDecline]         |
///   pure `?query`, or an empty `#`)           |                       |
/// | every other scheme (`data:`, `file:`,       | [LinkDecline]         |
///   `about:`, unknown)                        |                       |
///
/// [platform] is deliberately required even though today's table is
/// platform-uniform — v1's one platform split (Android's internal-nav
/// no-op) is exactly what v2 retires, and pinning the parameter keeps
/// every call site explicit about the platform it decides for (and
/// gives a future genuinely-platform-divergent rule its seam). Tests
/// assert BOTH platforms produce identical decisions across the table.
LinkDecision decideLinkTap(String url, {required TargetPlatform platform}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return const LinkDecline();

  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return LinkExternal(uri);
  }

  if (uri.scheme == 'mailto' || uri.scheme == 'tel') {
    return LinkConfirmExternal(uri);
  }

  if (uri.scheme.isEmpty) {
    // Same stripping the webview's _openInternalRelative applies: the
    // raw href minus any fragment/query suffix.
    final target = url.split('#').first.split('?').first;
    if (target.isEmpty) {
      // pure #fragment (anchor jump) or pure ?query (nothing to do).
      if (uri.hasFragment && uri.fragment.isNotEmpty) {
        return LinkFragment(uri.fragment);
      }
      return const LinkDecline();
    }
    final lower = target.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
      return const LinkDecline();
    }
    return LinkInternalMd(target);
  }

  return const LinkDecline();
}
