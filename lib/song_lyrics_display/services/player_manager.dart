import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

enum RepeatMode { off, one, all }

class PlayerManager {
  // ─────────────────────────────────────────
  // AUDIO PLAYER
  // ─────────────────────────────────────────
  static final AudioPlayer player = AudioPlayer();

  static bool _initialized = false;

  static ValueNotifier<List<Map<String, dynamic>>> globalSongs =
      ValueNotifier<List<Map<String, dynamic>>>([]);

  static final ValueNotifier<Map<String, dynamic>?> current =
      ValueNotifier<Map<String, dynamic>?>(null);

  static final ValueNotifier<bool> isPlaying =
      ValueNotifier<bool>(false);

  static final ValueNotifier<Duration> position =
      ValueNotifier<Duration>(Duration.zero);

  static final ValueNotifier<Duration> duration =
      ValueNotifier<Duration>(Duration.zero);

  static final ValueNotifier<RepeatMode> repeatMode =
      ValueNotifier<RepeatMode>(RepeatMode.all);

  static final ValueNotifier<bool> shuffle =
      ValueNotifier<bool>(false);

  // ─────────────────────────────────────────
  // RECENTLY PLAYED
  // ─────────────────────────────────────────
  static List<Map<String, dynamic>> recentlyPlayed = [];

  static void addToRecentlyPlayed(Map<String, dynamic> song) {
    final id = song['id'] ?? song['musicUrl'];

    final updatedSong = globalSongs.value.firstWhere(
      (s) => s['id'] == id || s['musicUrl'] == id,
      orElse: () => song,
    );

    recentlyPlayed.removeWhere(
      (s) => s['id'] == id || s['musicUrl'] == id,
    );

    recentlyPlayed.insert(0, updatedSong);
  }

  // ─────────────────────────────────────────
  // PERSISTENCE (JSON FILE)
  // ─────────────────────────────────────────
  static const String _fileName = 'saved_songs.json';

  static Future<File> _songsFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<void> saveGlobalSongs() async {
    try {
      final file = await _songsFile();
      await file.writeAsString(jsonEncode(globalSongs.value));
    } catch (e) {
      debugPrint('❌ Failed to save songs: $e');
    }
  }

  static Future<void> loadGlobalSongs() async {
    try {
      final file = await _songsFile();
      if (!await file.exists()) return;

      final data = jsonDecode(await file.readAsString());
      globalSongs.value =
          List<Map<String, dynamic>>.from(data);
    } catch (e) {
      debugPrint('❌ Failed to load songs: $e');
    }
  }

  // ─────────────────────────────────────────
  // INIT
static Future<void> init() async {
  if (_initialized) return;
  _initialized = true;

  // Load saved metadata ONCE
  await loadGlobalSongs();

  // Attach listeners ONLY once
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

  static Future<void> playSong(Map<String, dynamic> song) async {
    await init();
    try {
      await player.stop();
    } catch (_) {}

    final musicUrl = (song['musicUrl'] ?? '') as String;
    if (musicUrl.isEmpty) {
      isPlaying.value = false;
      return;
    }
    Map<String, dynamic> latestSongData = song;

  // 2. Lookup the song in the global source of truth (globalSongs)
  final globalIndex = globalSongs.value.indexWhere((s) => s['musicUrl'] == musicUrl);

  if (globalIndex != -1) {
    // 3. MERGE: Overwrite the incoming song map with the latest global metadata.
    // This ensures the current coverUrl and lyrics are used.
    latestSongData = {
      ...globalSongs.value[globalIndex],
      // Retain the index and list reference from the incoming 'song' map,
      // as they define the playlist context and order.
      'index': song['index'],
      'songs': song['songs'],
    };
  }

    try {
      if (musicUrl.startsWith('assets/')) {
        await player.play(
          AssetSource(musicUrl.replaceFirst('assets/', '')),
        );
      } else if (musicUrl.startsWith('http')) {
        await player.play(UrlSource(musicUrl));
      } else {
        await player.play(DeviceFileSource(musicUrl));
      }

      current.value = {
        ...latestSongData,
        'albumUrl': latestSongData['albumUrl'] ?? latestSongData['coverUrl'] ?? '',
      };
      isPlaying.value = true;
      addToRecentlyPlayed(latestSongData);
    } catch (e) {
      isPlaying.value = false;
      debugPrint('❌ Error playing song: $e');
    }
  }

  static Future<void> togglePlayPause() async {
    if (isPlaying.value) {
      await player.pause();
      isPlaying.value = false;
    } else if (current.value != null) {
      await player.resume();
      isPlaying.value = true;
    }
  }

  static Future<void> seek(Duration pos) async {
    await player.seek(pos);
  }

  static Future<void> stop() async {
    await player.stop();
    isPlaying.value = false;
  }

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

  // ─────────────────────────────────────────
  // UPDATE SONG DATA (WITH SAVE)
  // ─────────────────────────────────────────
  static void updateSongCover(String musicUrl, String newCover) {
    final gs = globalSongs.value;
    final idx = gs.indexWhere((s) => s['musicUrl'] == musicUrl);

    if (idx != -1) {
      gs[idx]['coverUrl'] = newCover;
      globalSongs.value = List.from(gs);
      saveGlobalSongs();
    }

    for (var s in recentlyPlayed) {
      if (s['musicUrl'] == musicUrl) {
        s['coverUrl'] = newCover;
      }
    }

    final cur = current.value;
    if (cur != null && cur['musicUrl'] == musicUrl) {
      cur['coverUrl'] = newCover;
      current.value = Map.from(cur);
    }
  }

static void updateLyrics(String musicUrl, String lyrics) {
  final gs = globalSongs.value;
  final idx = gs.indexWhere((s) => s['musicUrl'] == musicUrl);

  if (idx != -1) {
    gs[idx]['lyrics'] = lyrics;
    globalSongs.value = List.from(gs);
    saveGlobalSongs();
  }
  
  // 🔥 ADDED: Update the currently playing song's state
  final cur = current.value;
  if (cur != null && cur['musicUrl'] == musicUrl) {
    cur['lyrics'] = lyrics;
    current.value = Map.from(cur); // Trigger listeners
  }
}

  // ─────────────────────────────────────────
  // SONG COMPLETION
  // ─────────────────────────────────────────
  static Future<void> _handleSongCompletion() async {
    final cur = current.value;
    if (cur == null) return;

    final songs = cur['songs'] as List<Map<String, dynamic>>?;
    int? index = cur['index'];

    if (songs == null || index == null) return;

    if (repeatMode.value == RepeatMode.one) {
      await playSong({
        ...songs[index],
        'index': index,
        'songs': songs,
      });
    } else if (shuffle.value) {
      int next;
      do {
        next = Random().nextInt(songs.length);
      } while (next == index && songs.length > 1);
      index = next;
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
