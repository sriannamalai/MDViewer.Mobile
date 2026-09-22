/// Wiki-link (`[[Page Name]]`) resolution against the vault (issue #10).
///
/// The plugin resolves `[[Page Name]]` into an ordinary [MdvLink]
/// (`tree.dart`'s doc comment) whose `url` is EITHER what the
/// render-time resolver (`MdvResolveKind.wikiLink`) returns, or — when
/// no resolver answers — the plugin's own naive `.md`-suffix fallback
/// (`"Page Name"` → `"Page Name.md"`), which almost never matches an
/// actual vault-relative path (case, spacing, or directory differences),
/// so the resulting link renders styled but is silently unresolvable by
/// either engine's internal-`.md` navigation — exactly the shipped
/// defect this module fixes.
///
/// [wikiLinkResolver] supplies a SMARTER resolver instead: match the
/// wiki-link's raw target against every Markdown file's vault-relative
/// path by file STEM (case-insensitive), the same rule a real wiki
/// implementation uses (authors never spell out an extension or worry
/// about case in `[[...]]`). Both engines' render calls
/// (`DocRenderer.renderTree`/`DocRenderer.render`) accept this exactly
/// like the existing image resolver, so navigation Just Works through
/// the SAME internal-`.md` link path (`link_policy.dart`'s
/// [LinkInternalMd]) once resolved — no new tap-time special case needed
/// for the resolved case.
///
/// An ambiguous (more than one same-stem file) or unresolved (zero)
/// target can't be answered with a normal path, so it resolves to the
/// [wikiSearchUri] marker instead — a reserved, non-network URI scheme
/// [link_policy.dart]'s [LinkOpenSearch] decision recognizes and reroutes
/// to opening Search pre-filled with the raw target, so the user
/// disambiguates (or discovers there's no such page) rather than hitting
/// a silent no-op.
library;

import 'package:mdviewer/mdviewer.dart';
import 'package:path/path.dart' as p;

/// A reserved, non-network URI scheme [wikiSearchUri] emits. Recognized
/// by `link_policy.dart`'s [LinkOpenSearch] decision (both engines route
/// through it — the native tap table directly, the webview navigation
/// delegate via the same scheme check) and rerouted to opening Search;
/// never dereferenced as a real URL. Safe to round-trip verbatim through
/// the render pipeline: a resolver-returned URL is host-trusted
/// (`tree.dart`'s [MdvLink] doc comment — "Resolver-returned URLs are
/// host-trusted and carried verbatim"), so it skips the plugin's own
/// safe-URL scheme filtering that would otherwise block an unknown
/// scheme.
const String wikiSearchScheme = 'mdvwiki';

/// The `mdvwiki://search?q=<query>` marker URL for [query] — see
/// [wikiSearchScheme]'s doc comment.
Uri wikiSearchUri(String query) => Uri(
  scheme: wikiSearchScheme,
  host: 'search',
  queryParameters: {'q': query},
);

/// Resolves a wiki-link's raw [target] (`[[Page Name]]`'s inner text,
/// BEFORE the plugin's own `.md`-suffix fallback) against [mdRelPaths]
/// (every Markdown file's vault-relative path in the SAME vault as the
/// linking document — wiki-links are vault-wide, not scoped to any one
/// directory, so this is deliberately not [VaultPath.resolve]'s
/// directory-relative walk).
///
/// Exactly one file whose stem (filename minus its `.md`/`.markdown`
/// extension) matches [target], case-insensitively: returns that file's
/// path EXPRESSED RELATIVE TO [fromRelPath]'s directory (via
/// `package:path`'s posix arithmetic — vault paths are always
/// `/`-separated regardless of host platform), so the result round-trips
/// through [VaultPath.resolve] exactly like an authored relative `.md`
/// link (including a `../`-prefixed climb when the match lives in a
/// different directory) — no new resolution code needed on the tap side.
///
/// Zero matches (unresolved) or more than one (ambiguous): returns the
/// [wikiSearchUri] marker for [target] instead, so the caller can hand
/// the decision to the user via Search rather than guessing.
String resolveWikiLinkUrl({
  required String fromRelPath,
  required String target,
  required Iterable<String> mdRelPaths,
}) {
  final wanted = _stem(target).toLowerCase();
  String? matched;
  var matchCount = 0;
  for (final path in mdRelPaths) {
    if (_stem(path).toLowerCase() != wanted) continue;
    matchCount++;
    matched = path;
    if (matchCount > 1) break; // already ambiguous — no need to keep scanning
  }
  if (matchCount != 1) return wikiSearchUri(target).toString();

  final fromDir = p.posix.dirname(fromRelPath);
  return p.posix.relative(matched!, from: fromDir);
}

/// [path]'s file stem: the last `/`-segment with any trailing
/// `.extension` stripped. A leading dot (a dotfile-style name with no
/// real extension, e.g. `.gitignore`) is NOT treated as the extension
/// marker — matches [VaultEntry.isMarkdown]'s own extension-matching
/// spirit, where a bare leading dot is part of the name, not a suffix.
String _stem(String path) {
  final base = path.split('/').last;
  final dot = base.lastIndexOf('.');
  return dot <= 0 ? base : base.substring(0, dot);
}

/// Builds the [MdvResolver] for wiki-links (ABI kind 2) ONLY — every
/// other kind (link, image) declines (`null`), so this composes safely
/// with an image resolver via [combineResolvers] without either
/// shadowing the other. [fromRelPath]/[mdRelPaths] are captured once per
/// render call (the Reader rebuilds this resolver fresh each time it
/// renders/renders-the-tree, exactly like it does for the image
/// resolver) — see [resolveWikiLinkUrl]'s doc comment for their meaning.
MdvResolver wikiLinkResolver({
  required String fromRelPath,
  required Iterable<String> mdRelPaths,
}) {
  return (MdvResolveKind kind, String target) {
    if (kind != MdvResolveKind.wikiLink) return null;
    return resolveWikiLinkUrl(
      fromRelPath: fromRelPath,
      target: target,
      mdRelPaths: mdRelPaths,
    );
  };
}

/// Chains [resolvers] in order: the first non-null answer wins. Lets the
/// Reader combine the image resolver ([DocImages.toResolver]) with
/// [wikiLinkResolver] into the single [MdvResolver] the plugin's render
/// calls accept — each already declines every kind it doesn't own
/// (images decline wiki-links and vice versa), so the order between them
/// doesn't matter in practice.
MdvResolver combineResolvers(List<MdvResolver> resolvers) {
  return (MdvResolveKind kind, String target) {
    for (final resolver in resolvers) {
      final url = resolver(kind, target);
      if (url != null) return url;
    }
    return null;
  };
}
