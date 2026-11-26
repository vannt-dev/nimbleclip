import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/models/subtitle_file.dart';
import 'package:nimble_clip/services/subtitles/srt_converter.dart';
import 'package:nimble_clip/services/subtitles/subtitles_file.dart';

void main() {
  group('webVttToSrt', () {
    test('numbers the cues and writes SubRip times', () {
      const vtt = '''WEBVTT
Kind: captions
Language: en

00:00:01.200 --> 00:00:03.360
All right, so here we are,

00:01:05.318 --> 00:01:07.000
the cool thing
''';
      expect(
        webVttToSrt(vtt),
        '1\n00:00:01,200 --> 00:00:03,360\nAll right, so here we are,\n\n'
        '2\n00:01:05,318 --> 00:01:07,000\nthe cool thing\n\n',
      );
    });

    test('reads times without hours, cue names, settings and notes', () {
      const vtt = '''WEBVTT

NOTE made by hand
and kept short

STYLE
::cue { color: yellow }

intro
01:02.5 --> 01:04.250 align:start position:10% line:0
<v Roger>Hello &amp; welcome</v>
<i>to the show</i>
''';
      expect(
        webVttToSrt(vtt),
        '1\n00:01:02,500 --> 00:01:04,250\nHello & welcome\n<i>to the show</i>\n\n',
      );
    });

    test('accepts Windows line endings and long videos', () {
      const vtt =
          'WEBVTT\r\n\r\n'
          '01:59:59.999 --> 02:00:01.000\r\nLast words\r\n';
      expect(
        webVttToSrt(vtt),
        '1\n01:59:59,999 --> 02:00:01,000\nLast words\n\n',
      );
    });

    test('skips cues with no text or no length', () {
      const vtt = '''WEBVTT

00:00:01.000 --> 00:00:02.000
<c> </c>

00:00:03.000 --> 00:00:03.000
nothing

00:00:04.000 --> 00:00:05.000
kept
''';
      expect(webVttToSrt(vtt), '1\n00:00:04,000 --> 00:00:05,000\nkept\n\n');
    });

    test('shows each line of rolling speech captions once', () {
      // As served for a video's speech-recognised captions. The lines of a
      // single space are part of the format.
      const vtt =
          'WEBVTT\nKind: captions\nLanguage: en\n\n'
          '00:00:00.320 --> 00:00:18.790 align:start position:0%\n'
          ' \n[Music]\n\n'
          '00:00:18.790 --> 00:00:18.800 align:start position:0%\n'
          ' \n \n\n'
          '00:00:18.800 --> 00:00:21.790 align:start position:0%\n'
          ' \nHere<00:00:19.039><c> we</c><00:00:19.359><c> go</c>'
          '<00:00:19.840><c> to</c>\n\n'
          '00:00:21.790 --> 00:00:21.800 align:start position:0%\n'
          'Here we go to\n \n\n'
          '00:00:21.800 --> 00:00:25.950 align:start position:0%\n'
          'Here we go to\n'
          'town.<00:00:22.800><c> You</c><00:00:23.039><c> know</c>'
          '<00:00:23.279><c> the</c><00:00:23.600><c> way</c>\n\n'
          '00:00:25.950 --> 00:00:25.960 align:start position:0%\n'
          'town. You know the way\n \n\n'
          '00:00:25.960 --> 00:00:29.109 align:start position:0%\n'
          'town. You know the way\nand so do I.\n';
      expect(
        webVttToSrt(vtt),
        '1\n00:00:00,320 --> 00:00:18,790\n[Music]\n\n'
        '2\n00:00:18,800 --> 00:00:21,790\nHere we go to\n\n'
        '3\n00:00:21,800 --> 00:00:25,950\ntown. You know the way\n\n'
        '4\n00:00:25,960 --> 00:00:29,109\nand so do I.\n\n',
      );
    });

    test('keeps a line said twice in written subtitles', () {
      const vtt = '''WEBVTT

00:00:01.000 --> 00:00:02.000
No!

00:00:02.000 --> 00:00:03.000
No!
''';
      expect(
        webVttToSrt(vtt),
        '1\n00:00:01,000 --> 00:00:02,000\nNo!\n\n'
        '2\n00:00:02,000 --> 00:00:03,000\nNo!\n\n',
      );
    });

    test('gives nothing for something that is not WebVTT', () {
      expect(webVttToSrt('<html>not subtitles</html>'), isEmpty);
    });
  });

  group('subtitles beside a video', () {
    test('take the video name with .srt', () {
      expect(
        subtitlesPathFor('/data/NimbleClip/My clip.mp4'),
        '/data/NimbleClip/My clip.srt',
      );
      expect(subtitlesPathFor(r'C:\v\a.b.webm'), r'C:\v\a.b.srt');
      expect(subtitlesPathFor('/v/noextension'), '/v/noextension.srt');
    });

    test('are written as SubRip, and not at all when empty', () async {
      final directory = Directory.systemTemp.createTempSync('srt_');
      addTearDown(() => directory.deleteSync(recursive: true));
      final video = '${directory.path}/clip.mp4';

      final written = await writeSubtitlesBeside(
        video,
        const SubtitleFile(
          languageCode: 'en',
          webVtt: 'WEBVTT\n\n00:01.000 --> 00:02.000\nHi\n',
        ),
      );
      expect(written, '${directory.path}/clip.srt');
      expect(
        File(written!).readAsStringSync(),
        '1\n00:00:01,000 --> 00:00:02,000\nHi\n\n',
      );

      expect(
        await writeSubtitlesBeside(
          '${directory.path}/other.mp4',
          const SubtitleFile(languageCode: 'en', webVtt: 'WEBVTT\n'),
        ),
        isNull,
      );
      expect(File('${directory.path}/other.srt').existsSync(), isFalse);
    });
  });
}
