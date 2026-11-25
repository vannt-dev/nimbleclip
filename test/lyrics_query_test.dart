import 'package:flutter_test/flutter_test.dart';
import 'package:nimble_clip/services/lyrics/lyrics_query.dart';

void main() {
  group('cleanTrackTitle', () {
    final cases = {
      'Song (Official Video)': 'Song',
      'Song [Official Music Video]': 'Song',
      'Song (Official Audio)': 'Song',
      'Song [Lyrics]': 'Song',
      'Song (Lyric Video)': 'Song',
      'Song (Visualizer)': 'Song',
      'Song [HD]': 'Song',
      'Song 【MV】': 'Song',
      'Song (feat. Someone)': 'Song',
      'Song [ft. Someone]': 'Song',
      'Song ft. Someone': 'Song',
      'Song feat. Someone (Official Video)': 'Song',
      'Artist ft. Guest - Song': 'Artist - Song',
      'Song | Official Video': 'Song',
      'Song (Acoustic)': 'Song (Acoustic)',
      'Song (Live at Wembley)': 'Song (Live at Wembley)',
      '  Song   Title  ': 'Song Title',
      'Soft': 'Soft',
      'Left': 'Left',
    };
    cases.forEach((title, expected) {
      test('"$title" becomes "$expected"', () {
        expect(cleanTrackTitle(title), expected);
      });
    });
  });

  group('cleanArtistName', () {
    test('drops the suffix of an auto-generated channel', () {
      expect(cleanArtistName('Artist - Topic'), 'Artist');
    });
    test('drops a trailing VEVO', () {
      expect(cleanArtistName('ArtistVEVO'), 'Artist');
    });
    test('drops a featured artist', () {
      expect(cleanArtistName('Artist feat. Guest'), 'Artist');
    });
    test('leaves a plain name alone', () {
      expect(cleanArtistName('Jay-Z'), 'Jay-Z');
    });
  });

  group('LyricsQuery.forDownload', () {
    test('takes the artist from an "Artist - Song" title', () {
      final query = LyricsQuery.forDownload(
        title: 'Artist - Song (Official Video)',
        author: 'ArtistVEVO',
        duration: const Duration(seconds: 200),
      )!;
      expect(query.artist, 'Artist');
      expect(query.track, 'Song');
      expect(query.duration, const Duration(seconds: 200));
    });

    test('takes the uploader as the artist otherwise', () {
      final query = LyricsQuery.forDownload(
        title: 'Song [Lyrics]',
        author: 'Artist - Topic',
      )!;
      expect(query.artist, 'Artist');
      expect(query.track, 'Song');
      expect(query.duration, isNull);
    });

    test('drops quotes around the track name', () {
      final query = LyricsQuery.forDownload(
        title: 'Artist - "Song"',
        author: 'Uploader',
      )!;
      expect(query.track, 'Song');
    });

    test('leaves the artist empty for an unknown uploader', () {
      final query = LyricsQuery.forDownload(title: 'Song', author: 'Unknown')!;
      expect(query.artist, isEmpty);
    });

    test('gives nothing when no track name is left', () {
      expect(
        LyricsQuery.forDownload(title: '(Official Video)', author: 'Artist'),
        isNull,
      );
    });
  });
}
