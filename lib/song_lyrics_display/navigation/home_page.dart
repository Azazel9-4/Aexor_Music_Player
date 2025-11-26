import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:complete_music_player/pages/account_info_page.dart';
import '../services/player_manager.dart';
import '../services/mini_player.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class HomePage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const HomePage({super.key, this.userData});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String background = 'assets/logo/bg/bg_icon.jpg';
  List<Map<String, dynamic>> songs = [];
  List<Map<String, dynamic>> searchResults = [];
  List<String> playlists = [];
  Map<String, List<Map<String, dynamic>>> playlistSongs = {};
  int _selectedIndex = 0;
  final TextEditingController searchController = TextEditingController();

  Map<String, dynamic> get currentUserInfo {
    if (widget.userData != null) return widget.userData!;
    final user = FirebaseAuth.instance.currentUser;
    return {
      'full_name': user?.displayName ?? 'User',
      'email': user?.email ?? '',
      'photo_url': user?.photoURL ?? '',
    };
  }

  @override
  void initState() {
    super.initState();
    PlayerManager.init();
    _loadSongs();
  }
Future<void> _deleteSong(int index) async {
  final song = songs[index];

  // 1️⃣ Stop the player if this song is currently playing
  if (PlayerManager.current.value?['musicUrl'] == song['musicUrl']) {
    PlayerManager.stop();  // <-- STOP the player
  }

  // 2️⃣ Delete local MP3
  try {
    final file = File(song['musicUrl']);
    if (await file.exists()) await file.delete();
  } catch (e) {
    print('Error deleting song file: $e');
  }

  // 3️⃣ Remove from Firestore if it exists
  if (song.containsKey('id')) {
    try {
      await FirebaseFirestore.instance.collection('songs').doc(song['id']).delete();
    } catch (e) {
      print('Error deleting song from Firestore: $e');
    }
  }

  // 4️⃣ Remove from local JSON
  try {
    final dir = await getApplicationDocumentsDirectory();
    final jsonFile = File('${dir.path}/songs.json');
    if (await jsonFile.exists()) {
      final content = await json.decode(await jsonFile.readAsString());
      List<Map<String, dynamic>> jsonList = List<Map<String, dynamic>>.from(content);
      jsonList.removeWhere((s) => s['musicUrl'] == song['musicUrl']);
      await jsonFile.writeAsString(json.encode(jsonList), flush: true);
    }
  } catch (e) {
    print('Error deleting song from JSON: $e');
  }

  // 5️⃣ Remove from in-memory list and refresh UI
  setState(() {
    songs.removeAt(index);
    searchResults = List.from(songs);
  });

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Song deleted successfully')),
  );
}

 
void _createPlaylist() {
  int newIndex = playlists.length + 1;
  String defaultName = "Playlist #$newIndex";
  TextEditingController renameCtrl = TextEditingController(text: defaultName);

  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1E1E1E),
      title: const Text("Create Playlist", style: TextStyle(color: Colors.white)),
      content: TextField(
        controller: renameCtrl,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: "Playlist Name",
          hintStyle: TextStyle(color: Colors.white54),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.pop(context);
          },
          child: const Text("Cancel"),
        ),
        TextButton(
          onPressed: () {
            setState(() {
              playlists.add(renameCtrl.text);
              playlistSongs[renameCtrl.text] = [];
            });
            Navigator.pop(context);
          },
          child: const Text("Create"),
        ),
      ],
    ),
  );
}

void _addSongToPlaylist(Map<String, dynamic> song) {
  if (playlists.isEmpty) {
    _createPlaylist();
    return;
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1B1B1B),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 10),
        const Text("Select Playlist",
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white24),

        // Playlist List
        ...playlists.map((p) {
          return ListTile(
            title: Text(p, style: const TextStyle(color: Colors.white)),
            onTap: () {
              setState(() {
                playlistSongs[p]!.add(song);
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text("Added to $p")),
              );
            },
          );
        }).toList(),

        const Divider(color: Colors.white24),

        ListTile(
          leading: const Icon(Icons.add, color: Colors.white),
          title: const Text("Create Playlist", style: TextStyle(color: Colors.white)),
          onTap: () {
            Navigator.pop(context);
            _createPlaylist();
          },
        ),
      ],
    ),
  );
}

void _openSongOptions(Map<String, dynamic> song, int index) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1C1C1C),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
    ),
    builder: (_) => Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.white),
            title: const Text("Add to Playlist", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _addSongToPlaylist(song);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.redAccent),
            title:
                const Text("Delete Song", style: TextStyle(color: Colors.redAccent)),
            onTap: () {
              Navigator.pop(context);
              _deleteSong(index);
            },
          ),
        ],
      ),
    ),
  );
}


Future<void> _loadSongs() async {
  final Set<String> addedIds = {};
  final List<Map<String, dynamic>> loadedSongs = [];

  // 1️⃣ Load local JSON (user-added songs)
  try {
    final dir = await getApplicationDocumentsDirectory();
    final localFile = File('${dir.path}/songs.json');
    if (await localFile.exists()) {
      for (var song in List<Map<String, dynamic>>.from(json.decode(await localFile.readAsString()))) {
        final songId = song['id'] ?? "${song['title']}_${song['artist']}";
        if (!addedIds.contains(songId)) {
          loadedSongs.add(song);
          addedIds.add(songId);
        }
      }
    }
  } catch (e) {
    print("Error loading local songs.json: $e");
  }

  // 2️⃣ Load Firestore (user-added songs)
  try {
    final snapshot = await FirebaseFirestore.instance.collection('songs').get();
    for (var doc in snapshot.docs) {
      final data = doc.data();
      data['id'] = doc.id;
      if (!addedIds.contains(doc.id)) {
        loadedSongs.add(data);
        addedIds.add(doc.id);
      }
    }
  } catch (e) {
    print("Error loading songs from Firestore: $e");
  }

  // 3️⃣ Load assets (default songs)
  try {
    final data = await rootBundle.loadString('assets/data/songs.json');
    for (var song in List<Map<String, dynamic>>.from(json.decode(data))) {
      final songId = song['id'] ?? "${song['title']}_${song['artist']}";
      // ✅ Skip asset if same ID already exists
      if (!addedIds.contains(songId)) {
        loadedSongs.add(song);
        addedIds.add(songId);
      }
    }
  } catch (e) {
    print("Error loading asset songs.json: $e");
  }

  setState(() {
    songs = loadedSongs;
    searchResults = List.from(songs);
  });
}



  ImageProvider<Object> coverImage(Map<String, dynamic> song) {
    final url = song['coverUrl'] ?? '';
    if (url.isEmpty) return const AssetImage('assets/logo/default_cover.jpg');
    if (url.startsWith('assets/')) return AssetImage(url);
    return FileImage(File(url));
  }

  void _searchSong(String query) {
    setState(() {
      searchResults = songs
          .where((song) =>
              song['title'].toString().toLowerCase().contains(query.toLowerCase()) ||
              song['artist'].toString().toLowerCase().contains(query.toLowerCase()))
          .toList();
    });
  }

  void _openLyrics(int index) {
    Navigator.pushNamed(context, '/lyrics', arguments: {'songs': songs, 'index': index});
  }

  void _showProfilePanel() {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (_) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF222222),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.info, color: Colors.white),
                  title: const Text("Account Information", style: TextStyle(color: Colors.white)),
                  onTap: () {
                    Navigator.pop(context);
                    showDialog(
                      context: context,
                      barrierColor: Colors.black.withOpacity(0.2),
                      builder: (_) => AccountInfoPage(userData: currentUserInfo),
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.white),
                  title: const Text("Logout", style: TextStyle(color: Colors.white)),
                  onTap: () async {
                    Navigator.pop(context);
                    PlayerManager.stop();
                    await FirebaseAuth.instance.signOut();
                    await GoogleSignIn().signOut();
                    if (mounted) Navigator.pushReplacementNamed(context, '/login');
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

Widget _buildHorizontalCard(Map<String, dynamic> song) {
  return GestureDetector(
    onTap: () {
      // Find the index in the main songs list
      final mainIndex = songs.indexWhere((s) => s['musicUrl'] == song['musicUrl']);
      if (mainIndex != -1) {
        _openLyrics(mainIndex);
      } else {
        // Optionally, play directly from recently played
        _openLyricsFromRecent(song);
      }
    },
    child: Container(
      width: 140,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Image(
              image: coverImage(song),
              width: 140,
              height: 140,
              fit: BoxFit.cover,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(song['title'],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(song['artist'],
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

// Optional fallback
void _openLyricsFromRecent(Map<String, dynamic> song) {
  Navigator.pushNamed(context, '/lyrics', arguments: {'songs': [song], 'index': 0});
}


Widget _buildHomeTab() {
  final firstName = currentUserInfo['full_name']?.split(' ').first ?? 'User';
  return Stack(
    children: [
      ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // Greeting
          Text(
            'Hello, $firstName',
            style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Aexor - your music companion',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w400),
          ),
          const SizedBox(height: 20),

          // Recently Played
          const Text(
            'Recently Played',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: PlayerManager.recentlyPlayed.length,
              itemBuilder: (context, i) =>
                  _buildHorizontalCard(PlayerManager.recentlyPlayed[i]),
            ),
          ),
          const SizedBox(height: 20),

          // Your Music
          const Text(
            'Your Music',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final song = songs[i];

            return Container(
              margin: const EdgeInsets.symmetric(vertical:2),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.55), // transparent black
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListTile(
                onTap: () async {
                  await PlayerManager.playSong({
                    ...songs[i],
                    'index': i,
                    'songs': songs,
                    'albumUrl': songs[i]['albumUrl'] ?? songs[i]['coverUrl'],
                  });
                  _openLyrics(i);

                  setState(() {
                    PlayerManager.addToRecentlyPlayed(songs[i]);
                  });
                },
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image(image: coverImage(song), width: 50, height: 50, fit: BoxFit.cover),
                ),
                title: Text(song['title'],
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: Text(song['artist'],
                    style: const TextStyle(color: Colors.white70, fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.more_vert, color: Colors.white),
                  onPressed: () => _openSongOptions(song, i),
                ),
              ),
            );
            },
          ),
          const SizedBox(height: 5), 
        ],
      ),

     Positioned(
        top: 10,
        right: 10,
        child: FloatingActionButton(
          backgroundColor: const Color(0xFF1DB954),
          child: const Icon(Icons.add, color: Colors.black),
          onPressed: () {
            Navigator.pushNamed(context, '/add_song').then((_) => _loadSongs());
          },
        ),
      ),
    ],
  );
}

  Widget _buildSearchTab() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          TextField(
            controller: searchController,
            onChanged: _searchSong,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Search songs...',
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: Colors.white10,
              prefixIcon: const Icon(Icons.search, color: Colors.white),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              itemCount: searchResults.length,
              itemBuilder: (context, i) {
                final song = searchResults[i];
                return ListTile(
                  onTap: () async {
                    // Find the index of the tapped song in the full songs list
                    final mainIndex = songs.indexWhere((s) => s['musicUrl'] == song['musicUrl']);

                    if (mainIndex != -1) {
                      await PlayerManager.playSong({
                        ...songs[mainIndex],
                        'index': mainIndex,
                        'songs': songs,
                        'albumUrl': songs[mainIndex]['albumUrl'] ?? songs[mainIndex]['coverUrl'],
                      });
                      _openLyrics(mainIndex);
                    }
                  },

                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image(image: coverImage(song), width: 50, height: 50, fit: BoxFit.cover),
                  ),
                  title: Text(song['title'],
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(song['artist'],
                      style: const TextStyle(color: Colors.white70, fontSize: 13)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

Widget _buildLibraryTab() {
  return Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        ElevatedButton.icon(
          onPressed: () {
            // add a new playlist
            setState(() {
              playlists.add('Playlist#${playlists.length + 1}');
            });
          },
          icon: const Icon(Icons.playlist_add),
          label: const Text('Add Playlist'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1DB954),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.builder(
            itemCount: playlists.length,
            itemBuilder: (context, i) {
              return ListTile(
                title: Text(playlists[i], style: const TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pushNamed(context, '/playlist', arguments: playlists[i]);
                },
              );
            },
          ),
        ),
      ],
    ),
  );
}

  Widget _buildAccountTab() {
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 44,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: const Color(0xFF1DB954),
            child: photoUrl == null ? const Icon(Icons.person, size: 44, color: Colors.black) : null,
          ),
          const SizedBox(height: 12),
          Text(currentUserInfo['full_name'] ?? 'User',
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(currentUserInfo['email'] ?? '', style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _showProfilePanel,
            child: const Text('Account Info & Logout'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1DB954)),
          )
        ],
      ),
    );
  }

 @override
Widget build(BuildContext context) {
  // Check if there is a current song to show the mini player
  final showMiniPlayer = PlayerManager.current.value != null;

  return Scaffold(
    backgroundColor: Colors.transparent,
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      elevation: 0,
      title: Text(
        ['Home', 'Search', 'Your Library', 'Account'][_selectedIndex],
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0),
      ),
    ),
    body: Stack(
      children: [
        Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
        Positioned.fill(child: Container(color: Colors.black.withOpacity(0.5))),
        SafeArea(
          child: Column(
            children: [
              Expanded(
                child: IndexedStack(
                  index: _selectedIndex,
                  children: [
                    _buildHomeTab(),
                    _buildSearchTab(),
                    _buildLibraryTab(),
                    _buildAccountTab()
                  ],
                ),
              ),
              if (showMiniPlayer)
                const MiniPlayer(), // This now occupies space instead of overlaying
            ],
          ),
        ),
      ],
    ),
    bottomNavigationBar: BottomNavigationBar(
      backgroundColor: const Color(0xFF121212),
      selectedItemColor: const Color(0xFF1DB954),
      unselectedItemColor: Colors.white70,
      currentIndex: _selectedIndex,
      type: BottomNavigationBarType.fixed,
      onTap: (i) => setState(() => _selectedIndex = i),
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
        BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Search'),
        BottomNavigationBarItem(icon: Icon(Icons.library_music_outlined), label: 'Library'),
        BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Account'),
      ],
    ),
  );
}
}
