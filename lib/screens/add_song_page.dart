import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';

class AddSongPage extends StatefulWidget {
  const AddSongPage({super.key});

  @override
  State<AddSongPage> createState() => _AddSongPageState();
}

class _AddSongPageState extends State<AddSongPage> {
  final TextEditingController titleController = TextEditingController();
  final TextEditingController artistController = TextEditingController();
  final TextEditingController lyricsController = TextEditingController();

  File? songFile;
  File? albumImage;
  bool isLoading = false;

  final AudioPlayer _audioPlayer = AudioPlayer();

  // -------------------------------------------------------------
  // Pick MP3
  // -------------------------------------------------------------
  Future<void> pickSongFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['mp3'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() => songFile = File(result.files.single.path!));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("MP3 selected: ${result.files.single.name}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking file: $e")),
      );
    }
  }

  // -------------------------------------------------------------
  // Pick Album Image
  // -------------------------------------------------------------
  Future<void> pickAlbumImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);

      if (result != null && result.files.single.path != null) {
        setState(() => albumImage = File(result.files.single.path!));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Album image selected")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error picking image: $e")),
      );
    }
  }

  // -------------------------------------------------------------
  // Save Song (Local JSON + Firestore)
  // -------------------------------------------------------------
Future<void> addSong() async {
  final user = FirebaseAuth.instance.currentUser;

  if (user == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("You must be logged in to add a song")),
    );
    return;
  }

  if (titleController.text.isEmpty ||
      artistController.text.isEmpty ||
      songFile == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text("Please fill Title, Artist, and select an MP3 file")),
    );
    return;
  }

  setState(() => isLoading = true);

  try {
    String sanitizedTitle = titleController.text
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(' ', '_');

    final appDir = await getApplicationDocumentsDirectory();

    // Save MP3
    final songsDir = Directory(path.join(appDir.path, 'songs'));
    if (!await songsDir.exists()) songsDir.createSync(recursive: true);

    final savedMp3 = await songFile!.copy(
      path.join(
          songsDir.path,
          '$sanitizedTitle-${DateTime.now().millisecondsSinceEpoch}.mp3'),
    );

    // Save album image (optional)
    String? savedAlbumPath;
    if (albumImage != null) {
      final albumsDir = Directory(path.join(appDir.path, 'albums'));
      if (!await albumsDir.exists()) albumsDir.createSync(recursive: true);

      final savedImg = await albumImage!.copy(
        path.join(
          albumsDir.path,
          '${DateTime.now().millisecondsSinceEpoch}_${path.basename(albumImage!.path)}',
        ),
      );
      savedAlbumPath = savedImg.path;
    }

    // ----- Firestore write with confirmation -----
    final docRef = FirebaseFirestore.instance.collection('songs').doc();
    await docRef.set({
      'title': titleController.text,
      'artist': artistController.text,
      'lyrics':
          lyricsController.text.isNotEmpty ? lyricsController.text : null,
      'albumUrl': savedAlbumPath,
      'createdBy': user.email,
      'localPath': savedMp3.path,
      'timestamp': FieldValue.serverTimestamp(),
    });

    print("Song saved to Firestore with ID: ${docRef.id}");
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Song added successfully!")),
    );

    // ----- Local JSON save -----
    final jsonFile = File(path.join(appDir.path, 'songs.json'));
    List<dynamic> list = [];

    if (await jsonFile.exists()) {
      final content = await jsonFile.readAsString();
      if (content.isNotEmpty) list = json.decode(content);
    }

    list.add({
      "id": docRef.id,  // <-- ADD THIS
      "title": titleController.text,
      "artist": artistController.text,
      "musicUrl": savedMp3.path,
      "lyrics": lyricsController.text,
      "coverUrl": savedAlbumPath ?? "",
    });


    await jsonFile.writeAsString(json.encode(list), flush: true);

    Navigator.pop(context);
  } catch (e, s) {
    print("Error saving song to Firestore: $e");
    print(s);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error saving song: $e")),
    );
  } finally {
    setState(() => isLoading = false);
  }
}


  Future<void> playSong() async {
    if (songFile == null || !await songFile!.exists()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("MP3 file missing!")),
      );
      return;
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(songFile!.path));
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------
  // UI BUILD
  // -------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
          leading: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new, // straight "<" style arrow
                color: Colors.white,
                size: 22,
              ),
              onPressed: () => Navigator.pop(context),),
        title: const Text(
          "Add Song",
          style: TextStyle(
            color: Color(0xFF1DB954),
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),

      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight,
                ),
                child: Padding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                  ),

                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [

                        _buildField(titleController, "Song Title", Icons.music_note),
                        const SizedBox(height: 16),

                        _buildField(artistController, "Artist", Icons.person),
                        const SizedBox(height: 16),

                        // Select MP3 + Play button
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.upload_file, color: Colors.black),
                                label: Text(
                                  songFile != null ? "MP3 Selected" : "Select MP3",
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.black),
                                ),
                                onPressed: pickSongFile,
                                style: buttonStyle(),
                              ),
                            ),
                            const SizedBox(width: 12),
                            ElevatedButton(
                              onPressed: playSong,
                              style: buttonStyle(small: true),
                              child: const Icon(Icons.play_arrow, color: Colors.black),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Select Image
                        ElevatedButton.icon(
                          icon: const Icon(Icons.image, color: Colors.black),
                          label: Text(
                            albumImage != null
                                ? "Album Image Selected"
                                : "Select Album Image",
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.black),
                          ),
                          onPressed: pickAlbumImage,
                          style: buttonStyle(),
                        ),
                        const SizedBox(height: 16),

                        // Lyrics (responsive height)
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.25,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white12,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: TextField(
                              controller: lyricsController,
                              maxLines: null,
                              expands: true,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                hintText: "Lyrics (Optional)",
                                hintStyle: TextStyle(color: Colors.white54),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Save Button
                        ElevatedButton(
                          onPressed: isLoading ? null : addSong,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1DB954),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: isLoading
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  "Save Song",
                                  style: TextStyle(
                                      color: Colors.black,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }


  Widget _buildField(
      TextEditingController controller, String label, IconData icon) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70),
          prefixIcon: Icon(icon, color: Colors.white70),
          border: InputBorder.none,
        ),
      ),
    );
  }

  ButtonStyle buttonStyle({bool small = false}) {
    return ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1DB954),
      minimumSize: small
          ? const Size(50, 50)
          : const Size(double.infinity, 50),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
