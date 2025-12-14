import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/player_manager.dart';


class LibraryTab extends StatefulWidget {
  final List<Map<String, dynamic>> allSongs;
  final List<String> playlists;
  final Map<String, List<Map<String, dynamic>>> playlistSongs;
  final Map<String, String> playlistDocIdMap; 
  final void Function(List<String>, Map<String, List<Map<String, dynamic>>>)? onUpdatePlaylists;

  const LibraryTab({
    super.key,
    required this.allSongs,
    required this.playlists,
    required this.playlistSongs,
    required this.playlistDocIdMap,
    this.onUpdatePlaylists,
  });

  @override
  State<LibraryTab> createState() => _LibraryTabState();
}

class _LibraryTabState extends State<LibraryTab> {
  String? selectedPlaylist;
  bool editMode = false;
  final currentUser = FirebaseAuth.instance.currentUser;
  final FirebaseFirestore firestore = FirebaseFirestore.instance;

  Stream<QuerySnapshot>? _playlistStream;
  
void _syncPlaylistsFromFirestore(QuerySnapshot snapshot) {
  setState(() {});

  // We will update the existing maps and lists by merging.
  // First, collect the new data from the snapshot.
  Set<String> snapshotPlaylistNames = {};

  for (var doc in snapshot.docs) {
    final name = doc['name'] ?? 'Unknown';
    snapshotPlaylistNames.add(name);
    widget.playlistDocIdMap[name] = doc.id;
    final rawSongs = List<Map<String, dynamic>>.from(doc['songs'] ?? []);
    widget.playlistSongs[name] = rawSongs.map(_resolveSong).toList();
  }

  // Remove playlists that are not in the snapshot
  widget.playlists.removeWhere((name) => !snapshotPlaylistNames.contains(name));
  widget.playlistSongs.removeWhere((key, value) => !snapshotPlaylistNames.contains(key));
  widget.playlistDocIdMap.removeWhere((key, value) => !snapshotPlaylistNames.contains(key));

  // Now, update the playlists list to match the order of the snapshot
  widget.playlists.clear();
  widget.playlists.addAll(snapshot.docs.map((doc) => doc['name'] ?? 'Unknown'));

  if (widget.onUpdatePlaylists != null) {
    widget.onUpdatePlaylists!(widget.playlists, widget.playlistSongs);
  }
}

  Map<String, dynamic> _resolveSong(Map<String, dynamic> song) {
    final id = song['id'] ?? song['musicUrl'];

    return PlayerManager.globalSongs.value.firstWhere(
      (s) => (s['id'] ?? s['musicUrl']) == id,
      orElse: () => song, // fallback if not found
    );
  }

  @override
  void initState() {
    super.initState();
    if (currentUser != null) {
      _playlistStream = firestore
          .collection('users')
          .doc(currentUser!.uid)
          .collection('playlists')
          .snapshots();
    }
  }

Future<void> _createPlaylist(String name) async {
  if (currentUser == null) return;
  final docRef = await firestore
      .collection('users')
      .doc(currentUser!.uid)
      .collection('playlists')
      .add({'name': name, 'image': '', 'songs': []});

  setState(() {
    widget.playlists.add(name);
    widget.playlistSongs[name] = [];
    widget.playlistDocIdMap[name] = docRef.id; // <-- add this line
  });

  if (widget.onUpdatePlaylists != null) {
    widget.onUpdatePlaylists!(widget.playlists, widget.playlistSongs);
  }
}


 Future<void> _addSong(String docId, Map<String, dynamic> song) async {
  if (currentUser == null) return;

  final docRef = firestore
      .collection('users')
      .doc(currentUser!.uid)
      .collection('playlists')
      .doc(docId);

  final doc = await docRef.get();
  List<Map<String, dynamic>> songs =
      List<Map<String, dynamic>>.from(doc['songs'] ?? []);

  final songId = song['id'] ?? song['musicUrl'];

  if (!songs.any((s) => (s['id'] ?? s['musicUrl']) == songId)) {
    songs.add(song);

    await docRef.update({'songs': songs});
    // ❗ DO NOT setState
    // ❗ DO NOT touch widget.playlistSongs
    // Firestore stream will update UI
  }
}


  Future<void> _removeSong(String docId, Map<String, dynamic> song) async {
    if (currentUser == null) return;
    final docRef = firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('playlists')
        .doc(docId);
    final doc = await docRef.get();
    List songs = List<Map<String, dynamic>>.from(doc['songs'] ?? []);
    final songId = song['id'] ?? song['musicUrl'];
    songs.removeWhere((s) => (s['id'] ?? s['musicUrl']) == songId);
    await docRef.update({'songs': songs});
  }

  Future<void> _reorderSongs(String docId, int oldIndex, int newIndex) async {
    if (currentUser == null) return;
    final docRef = firestore
        .collection('users')
        .doc(currentUser!.uid)
        .collection('playlists')
        .doc(docId);
    final doc = await docRef.get();
    List songs = List<Map<String, dynamic>>.from(doc['songs'] ?? []);
    final item = songs.removeAt(oldIndex);
    songs.insert(newIndex, item);
    await docRef.update({'songs': songs});
  }

_playSong(Map<String, dynamic> song, List<Map<String, dynamic>> playlist) {
  final resolvedPlaylist = playlist.map(_resolveSong).toList();
  final index = playlist.indexWhere((s) => (s['id'] ?? s['musicUrl']) == (song['id'] ?? song['musicUrl']));

  PlayerManager.playSong({
    ...resolvedPlaylist[index],
    'songs': resolvedPlaylist, // ✅ pass full playlist
    'index': index,
    'albumUrl': resolvedPlaylist[index]['albumUrl'] ?? resolvedPlaylist[index]['coverUrl'],
  });
}


Widget _albumImage(String? path) {
  if (path == null || path.isEmpty) {
    return const Icon(Icons.music_note, color: Colors.white70, size: 50);
  } else if (path.startsWith('http')) {
    return Image.network(path, fit: BoxFit.cover);
  } else if (path.startsWith('assets/')) {
    return Image.asset(path, fit: BoxFit.cover); // Keep full path
  } else {
    return Image.file(File(path), fit: BoxFit.cover);
  }
}


/// Updated: Use widget.allSongs (passed from HomePage) as the primary source
/// but fall back to PlayerManager.globalSongs if widget.allSongs is empty.
/// This ensures the Add Song dialog shows the same songs that HomePage has
/// (which fixes the issue where the dialog sometimes shows nothing).
Future<void> _showAddSongDialog(String docId) async {
  // Get the latest playlist songs
  List<Map<String, dynamic>> existingSongs = [];

  final doc = await firestore
      .collection('users')
      .doc(currentUser!.uid)
      .collection('playlists')
      .doc(docId)
      .get();

  existingSongs = List<Map<String, dynamic>>.from(doc['songs'] ?? []);

  // If this playlist is currently playing, merge with PlayerManager
  final currentSong = PlayerManager.current.value;
  if (currentSong != null) {
    final playingSongs = currentSong['songs'] as List<Map<String, dynamic>>?;
    final playingDocId = currentSong['playlistDocId'] as String?;
    if (playingSongs != null && playingDocId == docId) {
      existingSongs = playingSongs.map(_resolveSong).toList();
    }
  }

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    builder: (_) {
      return ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: PlayerManager.globalSongs,
        builder: (context, notifierSongs, _) {
          // Prioritise songs passed in from HomePage (widget.allSongs).
          // If that's empty, fall back to the global notifier.
          final allSongs = (widget.allSongs.isNotEmpty) ? widget.allSongs : notifierSongs;

          if (allSongs.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'Loading songs...',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          }

          return ListView.builder(
            itemCount: allSongs.length,
            itemBuilder: (context, index) {
              final song = allSongs[index];
              final songId = song['id'] ?? song['musicUrl'];

              final alreadyAdded = existingSongs.any(
                (s) => (s['id'] ?? s['musicUrl']) == songId,
              );

              if (alreadyAdded) return const SizedBox.shrink();

              return ListTile(
                title: Text(
                  song['title'] ?? 'Unknown',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  song['artist'] ?? '',
                  style: const TextStyle(color: Colors.white70),
                ),
                onTap: () {
                  _addSong(docId, song);

                  // If currently playing playlist, also update PlayerManager.current.songs
                  if (currentSong != null &&
                      currentSong['songs'] != null &&
                      currentSong['playlistDocId'] == docId) {
                    final updatedSongs = List<Map<String, dynamic>>.from(currentSong['songs']);
                    updatedSongs.add(song);
                    PlayerManager.current.value = {
                      ...currentSong,
                      'songs': updatedSongs,
                    };
                  }

                  Navigator.pop(context);
                },
              );
            },
          );
        },
      );
    },
  );
}



 Future<void> _showPlaylistDetails(String docId, String name, String image) async {
  final TextEditingController nameController = TextEditingController(text: name);
  String currentImage = image;

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    isScrollControlled: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setModalState) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: DraggableScrollableSheet(
            initialChildSize: 0.5,
            minChildSize: 0.3,
            maxChildSize: 0.7,
            expand: false,
            builder: (context, scrollController) {
              return ListView(
                controller: scrollController,
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Playlist Details',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 6),

                  // Image + Rename field row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Playlist Image
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: currentImage.isNotEmpty
                            ? (currentImage.startsWith('http')
                                ? Image.network(currentImage, width: 120, height: 120, fit: BoxFit.cover)
                                : Image.file(File(currentImage),
                                    width: 120, height: 120, fit: BoxFit.cover))
                            : Container(
                                width: 120,
                                height: 120,
                                color: Colors.grey[800],
                                child: const Icon(Icons.music_note, color: Colors.white, size: 60),
                              ),
                      ),
                      const SizedBox(width: 16),

                      // Rename field only
                      Expanded(
                        child: TextField(
                          controller: nameController,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          decoration: InputDecoration(
                            hintText: 'Rename Playlist',
                            hintStyle: const TextStyle(color: Colors.white54),
                            filled: true,
                            fillColor: const Color(0xFF2A2A2A),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Change Image Button
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
                      if (pickedFile != null) {
                        await firestore
                            .collection('users')
                            .doc(currentUser!.uid)
                            .collection('playlists')
                            .doc(docId)
                            .update({'image': pickedFile.path});
                        setModalState(() => currentImage = pickedFile.path); // update image in modal
                        setState(() {}); // update main UI
                      }
                    },
                    icon: const Icon(Icons.image, color: Colors.white),
                    label: const Text('Change Image', style: TextStyle(color: Colors.white)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A2A2A),
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Save and Cancel Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            await firestore
                                .collection('users')
                                .doc(currentUser!.uid)
                                .collection('playlists')
                                .doc(docId)
                                .update({
                              'name': nameController.text,
                              'image': currentImage,
                            });
                            setState(() {}); // update main UI
                            Navigator.pop(context);
                          },
                          child: const Text('Save', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A2A2A),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2A2A2A),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        );
      },
    ),
  );
}


  Widget _smallActionButton(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF232323), borderRadius: BorderRadius.circular(20)),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Center(
          child: Text('Please login to see playlists', style: TextStyle(color: Colors.white)));
    }

    if (selectedPlaylist != null) {
      final docId = selectedPlaylist!.split('|')[0];
      final playlistName = selectedPlaylist!.split('|')[1];

      return StreamBuilder<DocumentSnapshot>(
        stream: firestore
            .collection('users')
            .doc(currentUser!.uid)
            .collection('playlists')
            .doc(docId)
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final data = snapshot.data!;
          final rawSongs = List<Map<String, dynamic>>.from(data['songs'] ?? []);
          final songs = rawSongs.map(_resolveSong).toList();
          final image = (data['image'] ?? '') as String;

          return Scaffold(
            backgroundColor: const Color(0xFF0F0F0F),
            body: SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back, color: Colors.white),
                          onPressed: () => setState(() {
                            selectedPlaylist = null;
                            editMode = false;
                          }),
                        ),
                        Expanded(
                          child: Text(
                            playlistName,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: image.isNotEmpty
                        ? (image.startsWith('http')
                            ? Image.network(image, width: 220, height: 220, fit: BoxFit.cover)
                            : Image.file(File(image), width: 220, height: 220, fit: BoxFit.cover))
                        : Container(
                            width: 220,
                            height: 220,
                            child: const Icon(Icons.music_note, color: Colors.white, size: 80),
                          ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _smallActionButton(Icons.add, 'Add Song', () => _showAddSongDialog(docId)),
                      _smallActionButton(Icons.edit, editMode ? 'Done' : 'Edit', () {
                        setState(() => editMode = !editMode);
                      }),
                      _smallActionButton(Icons.info, 'Details', () => _showPlaylistDetails(docId, playlistName, image)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: songs.isEmpty
                        ? const Center(child: Text('No songs in this playlist', style: TextStyle(color: Colors.white70)))
                        : ReorderableListView.builder(
                            itemCount: songs.length,
                            onReorder: (oldIndex, newIndex) => _reorderSongs(docId, oldIndex, newIndex),
                            itemBuilder: (context, index) {
                              final song = songs[index];
                              final songImage = song['albumUrl'] ?? song['coverUrl'] ?? '';
                              final songTitle = (song['title'] ?? 'Unknown') as String;
                              final songArtist = (song['artist'] ?? '') as String;
                              return ListTile(
                                key: ValueKey(song['id'] ?? song['musicUrl']),
                                onTap: editMode ? null : () => _playSong(song, songs),
                                leading: editMode
                                    ? IconButton(
                                        icon: const Icon(Icons.remove_circle, color: Colors.redAccent),
                                        onPressed: () => _removeSong(docId, song),
                                      )
                                    : ClipRRect(
                                        borderRadius: BorderRadius.circular(6),
                                        child: SizedBox(
                                          width: 50,
                                          height: 50,
                                          child: _albumImage(songImage),
                                        ),
                                      ),
                                title: Text(songTitle, style: const TextStyle(color: Colors.white)),
                                subtitle: Text(songArtist, style: const TextStyle(color: Colors.white70)),
                                trailing: editMode
                                    ? const Icon(Icons.drag_handle, color: Colors.white70)
                                    : null,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    // Playlist list
return StreamBuilder<QuerySnapshot>(
  stream: _playlistStream,
  builder: (context, snapshot) {
    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPlaylistsFromFirestore(snapshot.data!);
    });

    final playlists = snapshot.data!.docs;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Your Playlists',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.add, color: Colors.white),
                  onPressed: () async {
                    // Determine the default name based on current number of playlists
                    final newIndex = playlists.length + 1;
                    final defaultName = 'New Playlist #$newIndex';
                    final controller = TextEditingController(text: defaultName);

                    // Dark themed dialog
                    final result = await showDialog<String?>(
                      context: context,
                      builder: (_) => Dialog(
                        backgroundColor: const Color(0xFF1C1C1C),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Create New Playlist',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: controller,
                                style: const TextStyle(color: Colors.white),
                                decoration: InputDecoration(
                                  hintText: 'Playlist Name',
                                  hintStyle: const TextStyle(color: Colors.white54),
                                  filled: true,
                                  fillColor: Colors.white10,
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
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text(
                                        'Cancel',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: ElevatedButton(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF1DB954),
                                        minimumSize: const Size(double.infinity, 50),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(25),
                                        ),
                                      ),
                                      onPressed: () {
                                        final name = controller.text.trim();
                                        if (name.isNotEmpty) {
                                          _createPlaylist(name);
                                          Navigator.pop(context, name);
                                        }
                                      },
                                      child: const Text(
                                        'Create',
                                        style: TextStyle(color: Colors.black),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                    if (result != null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Playlist '$result' created!")),
                      );
                    }
                  },
                ),

            ],
          ),
        ),
        Expanded(
          child: playlists.isEmpty
              ? const Center(
                  child: Text('No playlists yet', style: TextStyle(color: Colors.white54)),
                )
              : ListView.builder(
                  itemCount: playlists.length,
                  itemBuilder: (context, i) {
                    final doc = playlists[i];
                    final name = (doc['name'] ?? 'Unknown') as String;
                    final image = (doc['image'] ?? '') as String;
                    final songsCount = (doc['songs'] ?? []).length;

                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        onTap: () => setState(() => selectedPlaylist = '${doc.id}|$name'),
                        leading: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 50,
                            height: 50,
                            child: _albumImage(image),
                          ),
                        ),
                        title: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        subtitle: Text('$songsCount songs', style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        trailing: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, color: Colors.white),
                          itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
                            PopupMenuItem<String>(
                              value: 'delete',
                              child: Text('Delete', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                          onSelected: (String value) {
                            if (value == 'delete') {
                              showDialog(
                                context: context,
                                builder: (context) => AlertDialog(
                                  backgroundColor: const Color(0xFF1E1E1E),
                                  title: const Text('Confirm Delete', style: TextStyle(color: Colors.white)),
                                  content: Text('Delete playlist "$name"?', style: const TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Cancel', style: TextStyle(color: Colors.white)),
                                    ),
                                    TextButton(
                                      onPressed: () {
                                        doc.reference.delete();
                                        Navigator.pop(context);
                                      },
                                      child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                                    ),
                                  ],
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  },
);
}
}