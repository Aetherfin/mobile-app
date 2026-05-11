import 'package:flutter_test/flutter_test.dart';

import 'package:aetherfin/core/lyrics/lrc_parser.dart';
import 'package:aetherfin/utils/time_format.dart';

void main() {
  group('formatTrackDuration', () {
    test('mm:ss for sub-hour durations', () {
      expect(formatTrackDuration(Duration.zero), '00:00');
      expect(formatTrackDuration(const Duration(seconds: 7)), '00:07');
      expect(formatTrackDuration(const Duration(seconds: 75)), '01:15');
      expect(formatTrackDuration(const Duration(minutes: 42, seconds: 9)),
          '42:09');
    });

    test('hh:mm:ss once hours are present', () {
      expect(
          formatTrackDuration(
              const Duration(hours: 1, minutes: 2, seconds: 3)),
          '01:02:03');
      expect(formatTrackDuration(const Duration(hours: 13)), '13:00:00');
    });

    test('clamps negatives to zero', () {
      expect(formatTrackDuration(const Duration(seconds: -5)), '00:00');
    });
  });

  group('formatHourCount', () {
    test('returns minutes for sub-hour durations', () {
      expect(formatHourCount(Duration.zero), '0m');
      expect(formatHourCount(const Duration(minutes: 7)), '7m');
      expect(formatHourCount(const Duration(minutes: 59)), '59m');
    });

    test('rounds to whole hours once >= 1h', () {
      expect(formatHourCount(const Duration(minutes: 60)), '1h');
      expect(formatHourCount(const Duration(minutes: 89)), '1h');
      expect(formatHourCount(const Duration(minutes: 90)), '2h');
      expect(formatHourCount(const Duration(hours: 103)), '103h');
    });
  });

  group('formatCompactCount', () {
    test('< 1000: passes through', () {
      expect(formatCompactCount(0), '0');
      expect(formatCompactCount(42), '42');
      expect(formatCompactCount(999), '999');
    });

    test('1000–9999: one decimal K', () {
      expect(formatCompactCount(1000), '1.0K');
      expect(formatCompactCount(2247), '2.2K');
      expect(formatCompactCount(9999), '10.0K');
    });

    test('10K–999K: whole K', () {
      expect(formatCompactCount(10_000), '10K');
      expect(formatCompactCount(12_400), '12K');
      expect(formatCompactCount(999_499), '999K');
    });

    test('millions', () {
      expect(formatCompactCount(1_200_000), '1.2M');
      expect(formatCompactCount(42_000_000), '42M');
    });
  });

  group('parseLrc', () {
    test('synced lines are sorted by timestamp', () {
      const src = '''
[00:12.50] second
[00:02.10] first
[00:30.00] third
''';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 3);
      expect(lrc.lines[0].text, 'first');
      expect(lrc.lines[0].start, const Duration(seconds: 2, milliseconds: 100));
      expect(lrc.lines[1].text, 'second');
      expect(lrc.lines[2].text, 'third');
    });

    test('multi-timestamp lines expand into multiple lines', () {
      const src = '[00:01.00][00:05.00][00:09.00] chorus';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 3);
      expect(lrc.lines.map((l) => l.text).toSet(), {'chorus'});
      expect(lrc.lines[0].start, const Duration(seconds: 1));
      expect(lrc.lines[1].start, const Duration(seconds: 5));
      expect(lrc.lines[2].start, const Duration(seconds: 9));
    });

    test('metadata is collected into Lrc.meta', () {
      const src = '''
[ti:My Title]
[ar:My Artist]
[00:00.00] hello
''';
      final lrc = parseLrc(src);
      expect(lrc.meta['ti'], 'My Title');
      expect(lrc.meta['ar'], 'My Artist');
      expect(lrc.lines.length, 1);
      expect(lrc.lines.first.text, 'hello');
    });

    test('unparseable lines are skipped, not crashed', () {
      const src = '''
random non-LRC line
[xx:xx.xx] also not valid
[00:01.00] valid
''';
      final lrc = parseLrc(src);
      expect(lrc.lines.length, 1);
      expect(lrc.lines.first.text, 'valid');
    });

    test('activeIndex returns the largest line <= position', () {
      const src = '''
[00:00.00] a
[00:05.00] b
[00:10.00] c
''';
      final lrc = parseLrc(src);
      expect(lrc.activeIndex(Duration.zero), 0);
      expect(lrc.activeIndex(const Duration(seconds: 3)), 0);
      expect(lrc.activeIndex(const Duration(seconds: 5)), 1);
      expect(lrc.activeIndex(const Duration(seconds: 9)), 1);
      expect(lrc.activeIndex(const Duration(seconds: 10)), 2);
      expect(lrc.activeIndex(const Duration(seconds: 999)), 2);
    });
  });
}
