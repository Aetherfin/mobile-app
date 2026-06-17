import 'package:flutter_test/flutter_test.dart';
import 'package:aetherfin/core/local/m3u_parser.dart';

void main() {
  group('M3uParser', () {
    group('parse', () {
      test('parses standard M3U (just paths)', () {
        const content = '''file1.mp3
file2.mp3
file3.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 3);
        expect(entries[0].path, 'file1.mp3');
        expect(entries[1].path, 'file2.mp3');
        expect(entries[2].path, 'file3.mp3');
      });

      test('parses extended M3U with EXTINF entries', () {
        const content = '''#EXTM3U
#EXTINF:301,Radiohead - Karma Police
/radiohead/karma_police.mp3
#EXTINF:-1,TV Girl - Lovers Rock
/tvgirl/lovers_rock.flac''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 2);
        expect(entries[0].title, 'Karma Police');
        expect(entries[0].artist, 'Radiohead');
        expect(entries[0].duration?.inSeconds, 301);
        expect(entries[0].path, '/radiohead/karma_police.mp3');
        expect(entries[1].title, 'Lovers Rock');
        expect(entries[1].artist, 'TV Girl');
      });

      test('returns empty list for empty content', () {
        expect(M3uParser.parse(''), isEmpty);
        expect(M3uParser.parse('   '), isEmpty);
        expect(M3uParser.parse('\n\n\n'), isEmpty);
      });

      test('handles corrupt EXTINF line without crash', () {
        const content = '''#EXTINF:notanumber
/path/to/file.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 1);
        expect(entries[0].duration, isNull);
        expect(entries[0].path, '/path/to/file.mp3');
      });

      test('handles relative paths', () {
        const content = '''./music/file1.mp3
../shared/file2.mp3
subdir/file3.mp3''';
        final entries = M3uParser.parse(content);
        expect(entries.length, 3);
        expect(entries[0].path, './music/file1.mp3');
        expect(entries[1].path, '../shared/file2.mp3');
        expect(entries[2].path, 'subdir/file3.mp3');
      });
    });
  });
}
