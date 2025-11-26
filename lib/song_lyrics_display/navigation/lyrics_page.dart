import 'dart:math';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../services/player_manager.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:heroicons/heroicons.dart';

class LyricsPage extends StatefulWidget {
  const LyricsPage({super.key});

  @override
  State<LyricsPage> createState() => _LyricsPageState();
}

class _LyricsPageState extends State<LyricsPage> {
  String _lyrics = "Loading lyrics...";
  String _currentTitle = '';
  String _currentArtist = '';
  String _currentMusicUrl = '';
  String _currentCoverUrl = '';

  List<Map<String, dynamic>> _songs = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    PlayerManager.init();

    // Listen for song change
    PlayerManager.current.addListener(() {
      final song = PlayerManager.current.value;
      if (song == null || !mounted) return;

      setState(() {
        _currentIndex = song['index'];
        _currentTitle = song['title']?.toString() ?? '';
        _currentArtist = song['artist']?.toString() ?? '';
        _currentMusicUrl = song['musicUrl']?.toString() ?? '';
        _currentCoverUrl = song['coverUrl']?.toString() ?? '';
      });

      _loadLyrics(song);
    });

    // Listen for position/duration/isPlaying changes
    PlayerManager.position.addListener(() {
      if (mounted) setState(() {});
    });
    PlayerManager.duration.addListener(() {
      if (mounted) setState(() {});
    });
    PlayerManager.isPlaying.addListener(() {
      if (mounted) setState(() {});
    });

    // Auto-next logic
    PlayerManager.position.addListener(() {
      final pos = PlayerManager.position.value;
      final dur = PlayerManager.duration.value;

      if (dur.inSeconds > 0 && pos >= dur - const Duration(milliseconds: 500)) {
        if (!PlayerManager.isPlaying.value) {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted) return;

            if (PlayerManager.repeatMode.value == RepeatMode.one) {
              _updateSong();
            } else if (PlayerManager.shuffle.value) {
              _currentIndex = Random().nextInt(_songs.length);
              _updateSong();
            } else {
              _playNextSong();
            }
          });
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args =
        ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;

    _songs = List<Map<String, dynamic>>.from(args['songs'] as List);
    _currentIndex = args['index'] ?? 0;
    final resume = args['resume'] ?? false;

    final song = _songs[_currentIndex];

    _currentTitle = song['title']?.toString() ?? '';
    _currentArtist = song['artist']?.toString() ?? '';
    _currentMusicUrl = song['musicUrl']?.toString() ?? '';
    _currentCoverUrl = song['coverUrl']?.toString() ?? '';

    _loadLyrics(song);

    if (!resume) {
      _playCurrentSong();
    }
  }

Future<void> _loadLyrics(Map<String, dynamic> song) async {
  try {
    // 1️⃣ If song has lyrics stored (user-added)
    if (song['lyrics'] != null && song['lyrics'].toString().trim().isNotEmpty) {
      setState(() => _lyrics = song['lyrics']);
      return;
    }

    // 2️⃣ Otherwise load from assets (default songs)
    final filename = song['title'].toLowerCase().replaceAll(" ", "_");
    final data = await rootBundle.loadString('assets/logo/lyrics/$filename.txt');

    setState(() => _lyrics = data);

  } catch (e) {
    setState(() => _lyrics = "Lyrics not available for ${song['title']}.");
  }
}

Future<void> _playCurrentSong() async {
  final song = {
    'title': _currentTitle,
    'artist': _currentArtist,
    'musicUrl': _currentMusicUrl,    // asset or localPath
    'coverUrl': _currentCoverUrl,
    'lyrics': _songs[_currentIndex]['lyrics'],
    'index': _currentIndex,
    'songs': _songs,
  };

  await PlayerManager.playSong(song);
}


void _playNextSong() {
  setState(() {
    _currentIndex = PlayerManager.shuffle.value
        ? Random().nextInt(_songs.length)
        : (_currentIndex + 1) % _songs.length;
  });
  _updateSong();
}

void _playPreviousSong() {
  setState(() {
    _currentIndex = PlayerManager.shuffle.value
        ? Random().nextInt(_songs.length)
        : (_currentIndex - 1 + _songs.length) % _songs.length;
  });
  _updateSong();
}

void _updateSong() {
  final song = _songs[_currentIndex];

  setState(() {
    _currentTitle = song['title']?.toString() ?? '';
    _currentArtist = song['artist']?.toString() ?? '';
    _currentMusicUrl = song['musicUrl']?.toString() ?? song['localPath']?.toString() ?? '';
    _currentCoverUrl = song['coverUrl']?.toString() ?? '';
  });

  _loadLyrics(song);
  _playCurrentSong();
}


void _toggleShuffle() {
  PlayerManager.shuffle.value = !PlayerManager.shuffle.value;
  setState(() {});
}

String _formatTime(Duration d) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  return "${twoDigits(d.inMinutes.remainder(60))}:${twoDigits(d.inSeconds.remainder(60))}";
}

ImageProvider _coverImage(String url) {
  if (url.startsWith('assets/')) return AssetImage(url);
  return FileImage(File(url));
}


@override
Widget build(BuildContext context) {
  return Scaffold(
    backgroundColor: const Color.fromARGB(255, 73, 70, 70),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    body: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Album Cover
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Container(
              key: ValueKey(_currentCoverUrl),
              width: MediaQuery.of(context).size.width * 0.8,
              height: MediaQuery.of(context).size.width * 0.8,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                image: DecorationImage(
                  image: _coverImage(_currentCoverUrl),
                  fit: BoxFit.cover,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black54,
                    blurRadius: 12,
                    offset: const Offset(2, 4),
                  ),
                ],
              ),
            ),
          ),

          // Title & Artist
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            child: Column(
              key: ValueKey(_currentTitle + _currentArtist),
              children: [
                Text(
                  _currentTitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  "by $_currentArtist",
                  style: const TextStyle(
                    fontSize: 18,
                    color: Color.fromARGB(200, 255, 255, 255),
                  ),
                ),
                const SizedBox(height: 75),
              ],
            ),
          ),

          // Slider & timing
        ValueListenableBuilder(
          valueListenable: PlayerManager.position,
          builder: (_, pos, __) {
            final dur = PlayerManager.duration.value;
            final pos = PlayerManager.position.value;

            return Column(
              children: [
                // Modern styled slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: const Color.fromARGB(255, 1, 253, 77),
                    inactiveTrackColor: Colors.white24,
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    thumbColor: const Color.fromARGB(255, 4, 250, 78),
                    overlayColor: const Color.fromARGB(50, 4, 250, 78),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                  ),
                  child: Slider(
                    value: pos.inSeconds.toDouble().clamp(
                          0,
                          dur.inSeconds.toDouble(),
                        ),
                    max: dur.inSeconds.toDouble() > 0 ? dur.inSeconds.toDouble() : 1,
                    onChanged: (value) => PlayerManager.seek(
                      Duration(seconds: value.toInt()),
                    ),
                  ),
                ),

                  const SizedBox(height: 4),

                  // Timing Row
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(pos),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                      Text(
                        _formatTime(dur),
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 10),

          // Playback Controls
          ValueListenableBuilder(
            valueListenable: PlayerManager.isPlaying,
            builder: (_, playing, __) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Repeat
                  ValueListenableBuilder<RepeatMode>(
                    valueListenable: PlayerManager.repeatMode,
                    builder: (context, repeatMode, _) {
                      IconData icon;
                      Color color;
                      switch (repeatMode) {
                        case RepeatMode.off:
                          icon = Symbols.repeat;
                          color = Colors.white70;
                          break;
                        case RepeatMode.one:
                          icon = Symbols.repeat_one;
                          color = const Color.fromARGB(255, 4, 231, 121);
                          break;
                        case RepeatMode.all:
                          icon = Symbols.repeat;
                          color = const Color.fromARGB(255, 4, 231, 121);
                          break;
                      }
                      return IconButton(
                        icon: Icon(icon, color: color),
                        iconSize: 30,
                        onPressed: PlayerManager.toggleRepeatMode,
                      );
                    },
                  ),

                  IconButton(
                    icon: HeroIcon(
                      HeroIcons.chevronLeft, // previous icon
                      style: HeroIconStyle.solid, // use solid for filled icon
                      color: Colors.white,
                      size: 50,
                    ),
                    onPressed: _playPreviousSong,
                  ),

                  InkWell(
                    onTap: PlayerManager.togglePlayPause,
                    borderRadius: BorderRadius.circular(50),
                    child: Container(
                      width: 70,
                      height: 70,
                      decoration: const BoxDecoration(
                        color: Color.fromARGB(255, 4, 250, 78),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        playing ? Icons.pause : Icons.play_arrow, // simple modern icons
                        color: Colors.black,
                        size: 50,
                      ),
                    ),
                  ),


                  IconButton(
                    icon: HeroIcon(
                      HeroIcons.chevronRight, // next icon
                      style: HeroIconStyle.solid,
                      color: Colors.white,
                      size: 50,
                    ),
                    onPressed: _playNextSong,
                  ),

                  IconButton(
                    icon: Icon(
                      Symbols.shuffle,
                      color: PlayerManager.shuffle.value
                          ? const Color.fromARGB(255, 4, 231, 121)
                          : Colors.white70,
                    ),
                    iconSize: 30,
                    onPressed: _toggleShuffle,
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 20),

          Container(
            height: 350, // fixed height for the whole lyrics area
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 8,
                  offset: Offset(2, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Fixed header
                const Text(
                  "Lyrics",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 32,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                // Scrollable lyrics
                Expanded(
                  child: SingleChildScrollView(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 400),
                      child: Text(
                        _lyrics,
                        key: ValueKey(_lyrics),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          height: 1.5,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 6,
                              color: Colors.black54,
                              offset: Offset(1, 1),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),
        ],
      ),
    ),
  );
}
}
