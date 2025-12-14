import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/player_manager.dart';
import '../services/mini_player.dart';
import 'library_tab.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:complete_music_player/help_and_support.dart';
import 'package:google_nav_bar/google_nav_bar.dart';
import 'package:complete_music_player/screens/add_song_page.dart'; // make sure this exists

class HomePage extends StatefulWidget {
  final Map<String, dynamic>? userData;
  const HomePage({super.key, this.userData});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final String background = 'assets/logo/bg/bg_icon.jpg';

  // removed cached _tabs to ensure LibraryTab receives fresh props on each rebuild

  List<Map<String, dynamic>> songs = [];
  List<Map<String, dynamic>> searchResults = [];
  List<String> playlists = [];
  Map<String, List<Map<String, dynamic>>> playlistSongs = {};
  Map<String, String> playlistDocIdMap = {};
  final Map<String, ImageProvider> _imageCache = {};

  int _selectedIndex = 0;
  final TextEditingController searchController = TextEditingController();
  Timer? _searchDebounce;

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
    _loadSongs();
    _loadPlaylists();
    PlayerManager.globalSongs.addListener(_onGlobalSongsUpdated);
  }

  @override
  void dispose() {
    PlayerManager.globalSongs.removeListener(_onGlobalSongsUpdated);
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _onGlobalSongsUpdated() {
    if (!mounted) return;

    setState(() {
      if (searchController.text.isNotEmpty) {
        _searchSong(searchController.text);
      } else {
        searchResults = List.from(songs);
      }

      _imageCache.clear();
    });
  }

  Future<void> _loadSongs() async {
    final Set<String> addedIds = {};
    final List<Map<String, dynamic>> loadedSongs = [];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/songs.json');
      if (await localFile.exists()) {
        final data = json.decode(await localFile.readAsString());
        for (var song in List<Map<String, dynamic>>.from(data)) {
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
      print("Error loading Firestore songs: $e");
    }

    try {
      final data = await rootBundle.loadString('assets/data/songs.json');
      for (var song in List<Map<String, dynamic>>.from(json.decode(data))) {
        final songId = song['id'] ?? "${song['title']}_${song['artist']}";
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
      searchResults = List.from(loadedSongs);
    });

    PlayerManager.globalSongs.value = List.from(loadedSongs);
  }

  Future<void> _loadPlaylists() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .collection('playlists')
          .get();

      final List<String> loadedPlaylists = [];
      final Map<String, List<Map<String, dynamic>>> loadedPlaylistSongs = {};
      final Map<String, String> docIds = {};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final name = data['name'] as String;
        loadedPlaylists.add(name);
        loadedPlaylistSongs[name] = List<Map<String, dynamic>>.from(data['songs'] ?? []);
        docIds[name] = doc.id;
      }

      setState(() {
        playlists = loadedPlaylists;
        playlistSongs = loadedPlaylistSongs;
        playlistDocIdMap = docIds;
      });
    } catch (e) {
      print("Error loading playlists: $e");
    }
  }

  ImageProvider coverImage(Map<String, dynamic> song) {
    final updatedSong = PlayerManager.globalSongs.value.firstWhere(
      (s) => s['musicUrl'] == song['musicUrl'],
      orElse: () => song,
    );

    final key = updatedSong['musicUrl'] ?? updatedSong['id'] ?? updatedSong['title'];

    final url = updatedSong['albumUrl'] ?? updatedSong['coverUrl'] ?? '';
    if (_imageCache.containsKey(key)) {
      final cached = _imageCache[key];
      if (cached is NetworkImage && cached.url != url) {
        _imageCache[key] = _imageFromUrl(url);
      }
    } else {
      _imageCache[key] = _imageFromUrl(url);
    }

    return _imageCache[key]!;
  }

  ImageProvider _imageFromUrl(String url) {
    if (url.isEmpty) return const AssetImage('assets/logo/default_cover.jpg');
    if (url.startsWith('assets/')) return AssetImage(url);
    if (url.startsWith('http')) return NetworkImage(url);
    return FileImage(File(url));
  }

  void _searchSong(String query) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 120), () {
      final q = query.toLowerCase();
      setState(() {
        searchResults = songs.where((song) =>
            song['title'].toString().toLowerCase().contains(q) ||
            song['artist'].toString().toLowerCase().contains(q)).toList();
      });
    });
  }

  void _openSongOptions(Map<String, dynamic> song, int index) {
    final isAssetSong = (song['musicUrl'] ?? '').startsWith('assets/');
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1C),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        children: [
          ListTile(
            leading: const Icon(Icons.playlist_add, color: Colors.white),
            title: const Text("Add to Playlist", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.pop(context);
              _addSongToPlaylist(song);
            },
          ),
          if (!isAssetSong)
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.redAccent),
              title: const Text("Delete Song", style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                _deleteSong(index);
              },
            ),
        ],
      ),
    );
  }

  // create playlist and return its id & name so callers can immediately add songs if needed
  Future<Map<String, String>?> _createPlaylist({String? initialName}) async {
    int newIndex = playlists.length + 1;
    String defaultName = initialName != null && initialName.trim().isNotEmpty ? initialName.trim() : "Playlist #$newIndex";
    TextEditingController renameCtrl = TextEditingController(text: defaultName);

    final result = await showDialog<Map<String, String>?>(
  context: context,
  builder: (_) => Dialog(
    backgroundColor: const Color(0xFF1C1C1C),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    child: Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            "Create New Playlist",
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: renameCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white10,
              hintText: "Playlist Name",
              hintStyle: const TextStyle(color: Colors.white54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text("Cancel", style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1DB954),
                  ),
                  onPressed: () async {
                    final playlistName = renameCtrl.text.trim();
                    if (playlistName.isEmpty) return;
                    try {
                      final uid = FirebaseAuth.instance.currentUser!.uid;
                      final docRef = await FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .collection('playlists')
                          .add({'name': playlistName, 'songs': [], 'image': ''});

                      if (!mounted) return;
                      setState(() {
                        playlists.add(playlistName);
                        playlistSongs[playlistName] = [];
                        playlistDocIdMap[playlistName] = docRef.id;
                      });

                      Navigator.pop(context, {'id': docRef.id, 'name': playlistName});
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Playlist '$playlistName' created!")),
                      );
                    } catch (e) {
                      print("Failed to create playlist: $e");
                      Navigator.pop(context, null);
                    }
                  },
                  child: const Text("Create", style: TextStyle(color: Colors.black)),
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  ),
);


    return result; // {'id': docId, 'name': playlistName} or null
  }

  // helper to add song to a playlist by doc id and update local state
  Future<void> _addSongToPlaylistByDoc({
    required String docId,
    required String playlistName,
    required Map<String, dynamic> song,
  }) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('playlists')
          .doc(docId)
          .update({
        'songs': FieldValue.arrayUnion([song])
      });

      // update local state
      if (!mounted) return;
      setState(() {
        if (!playlistSongs.containsKey(playlistName)) {
          playlistSongs[playlistName] = [];
        }
        playlistSongs[playlistName]!.add(song);
        playlistDocIdMap[playlistName] = docId;
        if (!playlists.contains(playlistName)) playlists.add(playlistName);
      });
    } catch (e) {
      print("Failed to add song to playlist: $e");
      // Optionally notify user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Failed to add song to playlist.")));
      }
    }
  }

  void _addSongToPlaylist(Map<String, dynamic> song) async {
    // Ensure user is signed in
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please login to manage playlists.")));
      return;
    }

    // If there are no playlists, create one and add the song to it
    if (playlists.isEmpty) {
      final created = await _createPlaylist();
      if (created == null) return;
      await _addSongToPlaylistByDoc(docId: created['id']!, playlistName: created['name']!, song: song);
      return;
    }

    // Build bottom sheet using current playlists names; we will resolve doc ids via playlistDocIdMap
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1B1B1B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ListView(
        shrinkWrap: true,
        physics: const BouncingScrollPhysics(),
        children: [
          const SizedBox(height: 10),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              "Select Playlist",
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          const Divider(color: Colors.white24),
          ...playlists.map((playlistName) {
            return ListTile(
              title: Text(playlistName, style: const TextStyle(color: Colors.white)),
              onTap: () async {
                Navigator.pop(context);

                // Resolve docId from map; fall back to querying Firestore if missing
                String? docId = playlistDocIdMap[playlistName];

                if (docId == null) {
                  try {
                    final uid = FirebaseAuth.instance.currentUser!.uid;
                    final snapshot = await FirebaseFirestore.instance
                        .collection('users')
                        .doc(uid)
                        .collection('playlists')
                        .where('name', isEqualTo: playlistName)
                        .get();

                    if (snapshot.docs.isNotEmpty) {
                      docId = snapshot.docs.first.id;
                      if (mounted) {
                        setState(() {
                          playlistDocIdMap[playlistName] = docId!;
                        });
                      }
                    }
                  } catch (e) {
                    print("Error fetching playlist docId: $e");
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Could not find playlist.")));
                    return;
                  }
                }

                if (docId == null) return;

                // check duplicate locally (better than duplicating to Firestore)
                final alreadyLocal = playlistSongs[playlistName]?.any((s) => (s['id'] ?? s['musicUrl']) == (song['id'] ?? song['musicUrl'])) ?? false;
                if (alreadyLocal) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Already in '$playlistName'")));
                  }
                  return;
                }

                await _addSongToPlaylistByDoc(docId: docId, playlistName: playlistName, song: song);
              },
            );
          }).toList(),
          const Divider(color: Colors.white24),
          ListTile(
            leading: const Icon(Icons.add, color: Colors.white),
            title: const Text("Create Playlist", style: TextStyle(color: Colors.white)),
            onTap: () async {
              Navigator.pop(context);
              final created = await _createPlaylist();
              if (created != null) {
                await _addSongToPlaylistByDoc(docId: created['id']!, playlistName: created['name']!, song: song);
              }
            },
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Future<void> _deleteSong(int index) async {
    final song = songs[index];
    final songKey = song['id'] ?? song['musicUrl'];

    if (PlayerManager.current.value?['musicUrl'] == song['musicUrl']) {
      PlayerManager.stop();
    }

    try {
      final file = File(song['musicUrl']);
      if (await file.exists()) await file.delete();
    } catch (_) {}

    if (song.containsKey('id')) {
      try {
        await FirebaseFirestore.instance
            .collection('songs')
            .doc(song['id'])
            .delete();
      } catch (_) {}
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final jsonFile = File('${dir.path}/songs.json');
      if (await jsonFile.exists()) {
        final content = json.decode(await jsonFile.readAsString());
        List<Map<String, dynamic>> jsonList =
            List<Map<String, dynamic>>.from(content);

        jsonList.removeWhere(
          (s) => (s['id'] ?? s['musicUrl']) == songKey,
        );

        await jsonFile.writeAsString(json.encode(jsonList), flush: true);
      }
    } catch (_) {}

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final playlistsSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('playlists')
            .get();

        for (final doc in playlistsSnap.docs) {
          final List playlistSongs =
              List<Map<String, dynamic>>.from(doc['songs'] ?? []);

          playlistSongs.removeWhere(
            (s) => (s['id'] ?? s['musicUrl']) == songKey,
          );

          await doc.reference.update({'songs': playlistSongs});
        }
      }
    } catch (_) {}

    setState(() {
      songs.removeAt(index);
      searchResults = List.from(songs);
    });
  }

  Widget _animatedTab(Widget child, int index) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: KeyedSubtree(
        key: ValueKey(index),
        child: child,
      ),
      transitionBuilder: (child, animation) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeInOut);
        final scale = Tween<double>(begin: 0.97, end: 1.0).animate(fade);

        return FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildHomeTab() {
  final firstName = currentUserInfo['full_name']?.split(' ').first ?? 'User';
  return Stack(
    children: [
      ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          Text('Hello, $firstName', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Aexor - your music companion', style: TextStyle(color: Colors.white70, fontSize: 16)),
          const SizedBox(height: 20),

          // Only show Recently Played if there are songs
          if (PlayerManager.recentlyPlayed.isNotEmpty) ...[
            const Text('Recently Played', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ValueListenableBuilder(
              valueListenable: PlayerManager.current,
              builder: (context, currentSong, child) {
                return SizedBox(
                  height: 200,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: PlayerManager.recentlyPlayed.length,
                    itemBuilder: (context, i) => RepaintBoundary(
                      child: _buildHorizontalCard(PlayerManager.recentlyPlayed[i]),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
          ],

          const Text('Your Music', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          ListView.builder(
            shrinkWrap: true,
            physics: const ClampingScrollPhysics(),
            cacheExtent: 1200,
            itemCount: songs.length,
            itemBuilder: (context, i) {
              final song = songs[i];
              return Container(
                margin: const EdgeInsets.symmetric(vertical: 2),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: Colors.black.withOpacity(0.55), borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  onTap: () async {
                    await PlayerManager.playSong({...song, 'index': i, 'songs': songs, 'albumUrl': song['albumUrl'] ?? song['coverUrl']});
                    setState(() => PlayerManager.addToRecentlyPlayed(song));
                  },
                  leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image(image: coverImage(song), width: 50, height: 50, fit: BoxFit.cover)),
                  title: Text(song['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(song['artist'], style: const TextStyle(color: Colors.white70, fontSize: 13)),
                  trailing: IconButton(icon: const Icon(Icons.more_vert, color: Colors.white), onPressed: () => _openSongOptions(song, i)),
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
            Navigator.of(context)
                .push(createSlideRightRoute(const AddSongPage()))
                .then((_) => _loadSongs());
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
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
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
                    final mainIndex = songs.indexWhere((s) => s['musicUrl'] == song['musicUrl']);
                    if (mainIndex != -1) {
                      await PlayerManager.playSong({...songs[mainIndex], 'index': mainIndex, 'songs': songs, 'albumUrl': songs[mainIndex]['albumUrl'] ?? songs[mainIndex]['coverUrl']});
                    }
                  },
                  leading: ClipRRect(borderRadius: BorderRadius.circular(8), child: Image(image: coverImage(song), width: 50, height: 50, fit: BoxFit.cover)),
                  title: Text(song['title'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  subtitle: Text(song['artist'], style: const TextStyle(color: Colors.white70, fontSize: 13)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLibraryTab() {
    return LibraryTab(
      allSongs: songs,
      playlists: playlists,
      playlistSongs: playlistSongs,
      playlistDocIdMap: playlistDocIdMap,
      onUpdatePlaylists: (updatedPlaylists, updatedSongs) {
        setState(() {
          playlists = updatedPlaylists;
          playlistSongs = updatedSongs;
        });
      },
    );
  }

  Widget _buildAccountTab() {
    final photoUrl = FirebaseAuth.instance.currentUser?.photoURL;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 60,
            backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
            backgroundColor: const Color(0xFF1DB954),
            child: photoUrl == null
                ? const Icon(Icons.person, size: 60, color: Colors.black)
                : null,
          ),
          const SizedBox(height: 16),
          Text(
            currentUserInfo['full_name'] ?? 'User',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            currentUserInfo['email'] ?? '',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 24),
          const Divider(color: Colors.white24, thickness: 1),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white),
            title: const Text("App Info", style: TextStyle(color: Colors.white)),
            onTap: () {
              showAboutDialog(
                context: context,
                applicationName: "Aexor Music",
                applicationVersion: "v1.0.0",
                applicationLegalese: "© 2025 Aexor Music",
                children: const [
                  SizedBox(height: 10),
                  Text("Terms of Service & Privacy Policy can be viewed on our website."),
                ],
              );
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF2A2A2A),
          ),
          const SizedBox(height: 7),
          ListTile(
            leading: const Icon(Icons.star_outline, color: Colors.white),
            title: const Text("Rate & Feedback", style: TextStyle(color: Colors.white)),
            onTap: () async {
              final Uri feedbackUrl = Uri.parse("https://docs.google.com/forms/d/e/1FAIpQLSeb97b1mDwFRQOBX2w-qOaLAkzZJQQ7Mkwehce29Ikeg2Cnqg/viewform?usp=sharing",);
              try {
                if (await canLaunchUrl(feedbackUrl)) {
                  await launchUrl(
                    feedbackUrl,
                    mode: LaunchMode.externalApplication,
                  );
                } else {
                  throw "Cannot launch URL";
                }
              } catch (e) {
                print("URL launch error: $e");
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Could not open feedback form.")),
                );
              }
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF2A2A2A),
          ),
          const SizedBox(height: 7),
          ListTile(
            leading: const Icon(Icons.help_outline, color: Colors.white),
            title: const Text("Help & Support", style: TextStyle(color: Colors.white)),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const HelpSupportPage()),
              );
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tileColor: const Color(0xFF2A2A2A),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: () async {
              final confirm = await showModalBottomSheet<bool>(
                context: context,
                backgroundColor: const Color(0xFF222222),
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
                ),
                builder: (context) => Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      const Text(
                        "Are you sure you want to logout?",
                        style: TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Colors.white70),
                                foregroundColor: Colors.white70,
                              ),
                              onPressed: () => Navigator.pop(context, false),
                              child: const Text("Cancel"),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1DB954), foregroundColor: Colors.black
                              ),
                              onPressed: () => Navigator.pop(context, true),
                              child: const Text("Logout"),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );

              if (confirm == true) {
                PlayerManager.stop();
                await FirebaseAuth.instance.signOut();
                await GoogleSignIn().signOut();
                if (mounted) Navigator.pushReplacementNamed(context, '/login');
              }
            },
            child: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1DB954),
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHorizontalCard(Map<String, dynamic> song) {
    return GestureDetector(
      onTap: () {
        final mainIndex = songs.indexWhere((s) => s['musicUrl'] == song['musicUrl']);
        if (mainIndex != -1) PlayerManager.addToRecentlyPlayed(songs[mainIndex]);
      },
      child: Container(
        width: 140,
        margin: const EdgeInsets.only(right: 12),
        decoration: BoxDecoration(color: const Color(0xFF1E1E1E), borderRadius: BorderRadius.circular(16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(borderRadius: const BorderRadius.vertical(top: Radius.circular(16)), child: Image(image: coverImage(song), width: 140, height: 140, fit: BoxFit.cover)),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(song['title'], overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(song['artist'], overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Route createSlideRightRoute(Widget page) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionDuration: const Duration(milliseconds: 300),
      reverseTransitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnim = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeOutCubic
        );

        final offsetTween = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: Offset.zero,
        ).animate(curvedAnim);

        return SlideTransition(
          position: offsetTween,
          child: child,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: false,
        elevation: 0,
        title: Text(['Home', 'Search', 'Your Library', 'Account'][_selectedIndex], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.0)),
      ),
      body: Stack(
        children: [
          Positioned.fill(child: Image.asset(background, fit: BoxFit.cover)),
          Positioned.fill(child: Container(color: Colors.black.withOpacity(0.5))),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: _animatedTab(
                    [
                      _buildHomeTab(),
                      _buildSearchTab(),
                      _buildLibraryTab(), // build fresh each time so it receives current props
                      _buildAccountTab(),
                    ][_selectedIndex],
                    _selectedIndex,
                  ),
                ),

                ValueListenableBuilder(
                  valueListenable: PlayerManager.current,
                  builder: (_, value, __) => value == null ? const SizedBox.shrink() : const MiniPlayer(),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          splashColor: Colors.transparent,
        ),
        child: Container(
          color: const Color(0xFF121212),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: GNav(
            gap: 8,
            activeColor: const Color(0xFF1DB954),
            color: Colors.white70,
            iconSize: 24,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            duration: const Duration(milliseconds: 300),
            tabBackgroundColor: Colors.white10,
            curve: Curves.easeInOut,
            haptic: true,
            selectedIndex: _selectedIndex,
            onTabChange: (index) => setState(() => _selectedIndex = index),
            tabs: const [
              GButton(icon: Icons.home_outlined, text: 'Home'),
              GButton(icon: Icons.search, text: 'Search'),
              GButton(icon: Icons.library_music_outlined, text: 'Library'),
              GButton(icon: Icons.person_outline, text: 'Account'),
            ],
          ),
        ),
      ),
    );
  }
}