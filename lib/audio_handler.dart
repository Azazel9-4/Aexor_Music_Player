import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class MyAudioHandler extends BaseAudioHandler with SeekHandler {
  final _player = AudioPlayer();

  MyAudioHandler() {
    // Broadcast playback state changes
    _player.playerStateStream.listen((state) {
      playbackState.add(playbackState.value.copyWith(
        playing: _player.playing,
        processingState: {
          ProcessingState.idle: AudioProcessingState.idle,
          ProcessingState.loading: AudioProcessingState.loading,
          ProcessingState.buffering: AudioProcessingState.buffering,
          ProcessingState.ready: AudioProcessingState.ready,
          ProcessingState.completed: AudioProcessingState.completed,
        }[_player.processingState]!,
      ));
    });

    _player.durationStream.listen((duration) {
      if (duration != null) {
        mediaItem.add(MediaItem(
          id: _player.audioSource?.sequence[0].tag.id ?? '',
          title: _player.audioSource?.sequence[0].tag.title ?? 'Unknown',
          artist: _player.audioSource?.sequence[0].tag.artist ?? '',
          duration: duration,
          artUri: Uri.parse(_player.audioSource?.sequence[0].tag.artUri ?? ''),
        ));
      }
    });
  }

  Future<void> playUrl(String url, {String? title, String? artist, String? artUri}) async {
    final item = MediaItem(
      id: url,
      title: title ?? 'Unknown Title',
      artist: artist ?? 'Unknown Artist',
      artUri: Uri.parse(artUri ?? ''),
    );
    mediaItem.add(item);

    await _player.setUrl(url);
    play();
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    // Optional: implement playlist next
  }

  @override
  Future<void> skipToPrevious() async {
    // Optional: implement playlist previous
  }
}
