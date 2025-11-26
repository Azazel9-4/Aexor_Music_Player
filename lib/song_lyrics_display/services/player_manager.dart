import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

enum RepeatMode { off, one, all }

class PlayerManager {
  static final AudioPlayer player = AudioPlayer();

  static final ValueNotifier<Map<String, dynamic>?> current =
      ValueNotifier<Map<String, dynamic>?>(null);
  static final ValueNotifier<bool> isPlaying = ValueNotifier<bool>(false);
  static final ValueNotifier<Duration> position =
      ValueNotifier<Duration>(Duration.zero);
  static final ValueNotifier<Duration> duration =
      ValueNotifier<Duration>(Duration.zero);
  static final ValueNotifier<RepeatMode> repeatMode =
      ValueNotifier<RepeatMode>(RepeatMode.all);
  static final ValueNotifier<bool> shuffle = ValueNotifier<bool>(false);

  // 🔹 RECENTLY PLAYED STACK
  static List<Map<String, dynamic>> recentlyPlayed = [];

  static void addToRecentlyPlayed(Map<String, dynamic> song) {
    recentlyPlayed.removeWhere((s) => s['musicUrl'] == song['musicUrl']); // avoid duplicates
    recentlyPlayed.insert(0, song); // newest at top
    if (recentlyPlayed.length > 10) recentlyPlayed.removeLast(); // optional limit
  }

  // 🔹 INIT
  static void init() {
    player.onPlayerComplete.listen((_) {
      _handleSongCompletion();
    });

    player.onDurationChanged.listen((d) {
      duration.value = d;
    });

    player.onPositionChanged.listen((p) {
      position.value = p;
    });
  }

  // 🔹 PLAY SONG
  static Future<void> playSong(Map<String, dynamic> song) async {
    try {
      await player.stop();
    } catch (_) {}

    final musicUrl = (song['musicUrl'] ?? '') as String;

    if (musicUrl.isEmpty) {
      isPlaying.value = false;
      return;
    }

    try {
      if (musicUrl.startsWith('assets/')) {
        // Play asset
        final sourcePath = musicUrl.replaceFirst('assets/', '');
        await player.play(AssetSource(sourcePath));
      } else {
        // Play local file
        await player.play(DeviceFileSource(musicUrl));
      }

      current.value = song;
      isPlaying.value = true;

      // 🔹 Add to recently played
      addToRecentlyPlayed(song);

    } catch (e) {
      isPlaying.value = false;
    }
  }

  // 🔹 PLAY / PAUSE TOGGLE
  static Future<void> togglePlayPause() async {
    if (isPlaying.value) {
      await player.pause();
      isPlaying.value = false;
    } else {
      if (current.value != null) {
        await player.resume();
        isPlaying.value = true;
      }
    }
  }

  // 🔹 SEEK
  static Future<void> seek(Duration pos) async {
    await player.seek(pos);
  }

  // 🔹 STOP
  static Future<void> stop() async {
    await player.stop();
    isPlaying.value = false;
  }

  // 🔹 TOGGLE REPEAT MODE
  static void toggleRepeatMode() {
    switch (repeatMode.value) {
      case RepeatMode.off:
        repeatMode.value = RepeatMode.one;
        break;
      case RepeatMode.one:
        repeatMode.value = RepeatMode.all;
        break;
      case RepeatMode.all:
        repeatMode.value = RepeatMode.off;
        break;
    }
  }

  // 🔹 HANDLE WHEN SONG ENDS
  static Future<void> _handleSongCompletion() async {
    final currentSong = current.value;
    if (currentSong == null) return;

    final songs = currentSong['songs'] as List<Map<String, dynamic>>?;
    var index = currentSong['index'] as int?;
    if (songs == null || index == null) return;

    // 🔹 Determine next song
    if (repeatMode.value == RepeatMode.one) {
      await playSong({
        ...songs[index],
        'index': index,
        'songs': songs,
      });
    } else if (shuffle.value) {
      int nextIndex;
      do {
        nextIndex = Random().nextInt(songs.length);
      } while (nextIndex == index && songs.length > 1);
      index = nextIndex;
      await playSong({
        ...songs[index],
        'index': index,
        'songs': songs,
      });
    } else if (repeatMode.value == RepeatMode.all) {
      index = (index + 1) % songs.length;
      await playSong({
        ...songs[index],
        'index': index,
        'songs': songs,
      });
    } else {
      await stop();
    }
  }
}
