import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import '../../core/api_client.dart';
import '../../core/media_cache.dart';
import '../../core/models.dart';

class PlayerService {
  PlayerService._();
  static final PlayerService i = PlayerService._();

  final player = AudioPlayer();
  List<Track> tracks = [];

  bool get loaded => player.audioSource != null;

  Future<void> play(List<Track> list, int index) async {
    tracks = list;
    final dir = await MediaCache.dir();
    final sources = <AudioSource>[
      for (final t in list)
        LockCachingAudioSource(
          Uri.parse(Api.i.abs(t.url)),
          headers: Api.i.authHeaders,
          cacheFile: File('${dir.path}/music_${t.id}.audio'),
          tag: MediaItem(
              id: t.id, title: t.title, artist: t.tag.isEmpty ? 'موزیک تمرکز' : t.tag),
        ),
    ];
    await player.setAudioSource(ConcatenatingAudioSource(children: sources), initialIndex: index);
    await player.setLoopMode(LoopMode.all);
    player.play();
  }

  Future<void> toggle() async => player.playing ? player.pause() : player.play();
  Future<void> next() => player.seekToNext();
  Future<void> prev() => player.seekToPrevious();
  Future<void> stop() async {
    await player.stop();
  }
}
