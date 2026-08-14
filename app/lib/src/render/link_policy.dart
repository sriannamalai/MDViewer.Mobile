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

/// Everything else is an explicit no-op: `mailto:`/`tel:`/`data:`/
/// `file:`/`about:`/unknown schemes, non-Markdown relative targets,
/// pure `#fragment` links (anchor jumps are line-less — a documented v2
/// native limitation, 1.0-train candidate; the webview engine handles
/// them in-page), and anything [Uri.tryParse] cannot parse.
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
/// | URL shape                                   | decision           |
/// |---------------------------------------------|--------------------|
/// | unparseable                                 | [LinkDecline]      |
/// | `http:`/`https:` (any case — Uri normalizes)| [LinkExternal]     |
/// | scheme-less ending `.md`/`.markdown` (any   | [LinkInternalMd]   |
/// |   case), after `#`/`?` stripping            |                    |
/// | scheme-less, anything else (non-md target,  | [LinkDecline]      |
/// |   pure `#fragment`, pure `?query`)          |                    |
/// | every other scheme (`mailto:`, `tel:`,      | [LinkDecline]      |
/// |   `data:`, `file:`, `about:`, unknown)      |                    |
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

  if (uri.scheme.isEmpty) {
    // Same stripping the webview's _openInternalRelative applies: the
    // raw href minus any fragment/query suffix.
    final target = url.split('#').first.split('?').first;
    if (target.isEmpty) return const LinkDecline(); // pure #fragment/?query
    final lower = target.toLowerCase();
    if (!lower.endsWith('.md') && !lower.endsWith('.markdown')) {
      return const LinkDecline();
    }
    return LinkInternalMd(target);
  }

  return const LinkDecline();
}
