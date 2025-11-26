import 'package:flutter/material.dart';
import 'player_manager.dart';
import 'package:heroicons/heroicons.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

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
            final albumCover = current['albumUrl'] as String? ?? current['coverUrl'] as String?;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  final currentSong = PlayerManager.current.value;
                  if (currentSong != null) {
                    final songsList = currentSong['songs'] as List<Map<String, dynamic>>?;
                    final index = currentSong['index'] as int?;
                    if (songsList != null && index != null) {
                      Navigator.pushNamed(
                        context,
                        '/lyrics',
                        arguments: {
                          'songs': songsList,
                          'index': index,
                          'resume': true,
                        },
                      );
                    }
                  }
                },
                child: Container(
                  height: 80,
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
                        height: 55,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.grey[800],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            albumCover ?? '',
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return const Icon(Icons.music_note, color: Colors.white70);
                            },
                          ),
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

                      // Playback Controls with spacing
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Previous
                          IconButton(
                            icon: HeroIcon(
                              HeroIcons.chevronLeft,
                              style: HeroIconStyle.solid,
                              color: Colors.white70,
                            ),
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

                          const SizedBox(width: 1), // spacing

                          // Play/Pause
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause_circle_filled : Icons.play_circle_fill,
                              color: const Color.fromARGB(255, 4, 250, 78),
                              size: 45,
                            ),
                            onPressed: PlayerManager.togglePlayPause,
                          ),

                          const SizedBox(width: 1), // spacing

                          // Next
                          IconButton(
                            icon: HeroIcon(
                              HeroIcons.chevronRight,
                              style: HeroIconStyle.solid,
                              color: Colors.white70,
                            ),
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
