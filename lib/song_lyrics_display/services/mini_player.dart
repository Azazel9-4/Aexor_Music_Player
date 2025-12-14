import 'dart:io';
import 'package:flutter/material.dart';
import 'player_manager.dart';
import 'package:heroicons/heroicons.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:complete_music_player/song_lyrics_display/navigation/lyrics_page.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  Widget _albumImage(String? path) {
    if (path == null || path.isEmpty) {
      return const Icon(Icons.music_note, color: Colors.white70);
    } else if (path.startsWith('assets/')) {
      return Image.asset(path, fit: BoxFit.cover, key: ValueKey(path));
    } else if (path.startsWith('http')) {
      return CachedNetworkImage(
        imageUrl: path,
        fit: BoxFit.cover,
        key: ValueKey(path),
        placeholder: (context, url) => const Icon(Icons.music_note, color: Colors.white70),
        errorWidget: (context, url, error) => const Icon(Icons.error),
      );
    } else {
      return Image.file(File(path), fit: BoxFit.cover, key: ValueKey(path));
    }
  }

void _openFullPlayerSlidingUp(BuildContext context, Map<String, dynamic> currentSong) {
  final songsList = currentSong['songs'] as List<Map<String, dynamic>>?;
  final index = currentSong['index'] as int?;

  if (songsList != null && index != null) {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) {
          return LyricsPage(); // LyricsPage will read arguments via ModalRoute
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;

          final tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 400),
        settings: RouteSettings(
          arguments: {
            'songs': songsList,
            'index': index,
            'resume': true,
          },
        ),
      ),
    );
  }
}


  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, dynamic>?>( 
      valueListenable: PlayerManager.current,
      builder: (context, current, _) {
        if (current == null) return const SizedBox.shrink();

        return ValueListenableBuilder<bool>(
          valueListenable: PlayerManager.isPlaying,
          builder: (context, isPlaying, _) {
            final title = current['title'] ?? '';
            final artist = current['artist'] ?? '';
            final albumCover = current['albumUrl'] as String?;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  final currentSong = PlayerManager.current.value;
                  if (currentSong != null) {
                    _openFullPlayerSlidingUp(context, currentSong);
                  }
                },
                // The rest of your MiniPlayer UI remains the same...
                child: Container(
                  height: 60,
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1C1C1C),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      // Album Art
                      Container(
                        width: 55,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[800],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _albumImage(albumCover),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Song Info
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              artist,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Playback Controls
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: HeroIcon(HeroIcons.chevronLeft, style: HeroIconStyle.solid, color: Colors.white70),
                            onPressed: () {
                              final currentSong = PlayerManager.current.value;
                              if (currentSong != null) {
                                final songsList = currentSong['songs'] as List<Map<String, dynamic>>?;
                                final index = currentSong['index'] as int?;
                                if (songsList != null && index != null) {
                                  final prevIndex = (index - 1 + songsList.length) % songsList.length;
                                  PlayerManager.playSong({
                                    ...songsList[prevIndex],
                                    'index': prevIndex,
                                    'songs': songsList,
                                    'albumUrl': songsList[prevIndex]['albumUrl'] ?? songsList[prevIndex]['coverUrl'],
                                  });
                                }
                              }
                            },
                          ),
                          const SizedBox(width: 1),
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: const Color.fromARGB(255, 4, 250, 78),
                              size: 35,
                            ),
                            onPressed: PlayerManager.togglePlayPause,
                          ),
                          const SizedBox(width: 1),
                          IconButton(
                            icon: HeroIcon(HeroIcons.chevronRight, style: HeroIconStyle.solid, color: Colors.white70),
                            onPressed: () {
                              final currentSong = PlayerManager.current.value;
                              if (currentSong != null) {
                                final songsList = currentSong['songs'] as List<Map<String, dynamic>>?;
                                final index = currentSong['index'] as int?;
                                if (songsList != null && index != null) {
                                  final nextIndex = (index + 1) % songsList.length;
                                  PlayerManager.playSong({
                                    ...songsList[nextIndex],
                                    'index': nextIndex,
                                    'songs': songsList,
                                    'albumUrl': songsList[nextIndex]['albumUrl'] ?? songsList[nextIndex]['coverUrl'],
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
