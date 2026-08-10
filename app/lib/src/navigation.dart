import 'package:flutter/material.dart';

import 'tokens.dart';
import 'vault/vault_entry.dart';

/// Pushes the Reader above the shell for [entry] — design/README.md
/// §Interactions: "Library → tap file → Reader (push)"; tabs stay as roots,
/// Reader is a plain [Navigator] push over whichever tab triggered it (so
/// the tab bar disappears while reading, matching design/screenshots/
/// 02-reader.png).
///
/// The real Reader screen lands in Task 5. Until then this pushes a
/// tokens-styled stand-in so the hook is fully wired and callable — Task 4
/// (Library rows) and Task 7 (Search results) call this rather than
/// building their own `Navigator.push`, and swapping the placeholder body
/// for the real Reader in Task 5 is a one-line change here.
Future<void> pushReader(BuildContext context, VaultEntry entry) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => _ReaderPlaceholder(entry: entry),
    ),
  );
}

class _ReaderPlaceholder extends StatelessWidget {
  const _ReaderPlaceholder({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Scaffold(
      backgroundColor: tokens.bg,
      appBar: AppBar(title: Text(entry.name)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            // TODO(task-5): replace with the real Reader (webview render,
            // scrollspy, bottom bar) per design/README.md §02.
            'Reader for "${entry.relPath}" lands in Task 5.',
            textAlign: TextAlign.center,
            style: TextStyle(color: tokens.text2),
          ),
        ),
      ),
    );
  }
}
