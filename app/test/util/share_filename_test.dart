import 'package:app/src/util/share_filename.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ShareFilename.forEntryName', () {
    test('replaces the .md extension with .html', () {
      expect(ShareFilename.forEntryName('Welcome.md'), 'Welcome.html');
    });

    test('replaces .markdown too, case-insensitively', () {
      expect(ShareFilename.forEntryName('Notes.MARKDOWN'), 'Notes.html');
      expect(ShareFilename.forEntryName('Notes.Markdown'), 'Notes.html');
    });

    test('preserves spaces (a safe character)', () {
      expect(
        ShareFilename.forEntryName('Getting Started.md'),
        'Getting Started.html',
      );
    });

    test('replaces path separators and other unsafe characters with _', () {
      expect(
        ShareFilename.forEntryName('a/b\\c:d*e?f"g<h>i|j.md'),
        'a_b_c_d_e_f_g_h_i_j.html',
      );
    });

    test('strips leading dots so the export is never a hidden file', () {
      expect(ShareFilename.forEntryName('.hidden.md'), 'hidden.html');
      expect(ShareFilename.forEntryName('...md'), 'document.html');
    });

    test('falls back to "document" only when sanitizing leaves nothing', () {
      // '.md' alone: stripping the extension leaves an empty base name.
      expect(ShareFilename.forEntryName('.md'), 'document.html');
      expect(ShareFilename.forEntryName(''), 'document.html');
    });

    test(
      'unsafe characters become _, not empty — a name of only slashes is not blank',
      () {
        // Path separators map to '_' rather than being dropped, so this is
        // "____.html", not the "document.html" fallback (there IS content
        // here, it's just all unsafe).
        expect(ShareFilename.forEntryName('////.md'), '____.html');
      },
    );

    test('a name with no markdown extension keeps its base name', () {
      expect(ShareFilename.forEntryName('README'), 'README.html');
    });
  });
}
