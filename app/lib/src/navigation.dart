import 'package:flutter/material.dart';

import 'screens/reader.dart';
import 'vault/vault_entry.dart';

/// Pushes the Reader above the shell for [entry] — design/README.md
/// §Interactions: "Library → tap file → Reader (push)"; tabs stay as roots,
/// Reader is a plain [Navigator] push over whichever tab triggered it (so
/// the tab bar disappears while reading, matching design/screenshots/
/// 02-reader.png).
///
/// Task 4 (Library rows) and Task 7 (Search results) call this rather than
/// building their own `Navigator.push`, so the destination — a
/// [ReaderScreen] as of Task 5 — only needs to change in one place.
///
/// [initialLine] (Task 7's Search results, and the open-with flow) scrolls
/// the Reader to that source line right after its first page load — see
/// [ReaderScreen.initialLine]'s doc comment.
Future<void> pushReader(
  BuildContext context,
  VaultEntry entry, {
  int? initialLine,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          ReaderScreen(entry: entry, initialLine: initialLine),
    ),
  );
}
