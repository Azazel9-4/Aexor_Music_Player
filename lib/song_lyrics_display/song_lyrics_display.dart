import 'package:flutter/material.dart';
import 'navigation/home_page.dart';
import 'navigation/lyrics_page.dart';

class SongLyricsDisplayApp extends StatelessWidget {
  const SongLyricsDisplayApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Aexor',
      theme: ThemeData(
        primarySwatch: Colors.deepPurple,
        scaffoldBackgroundColor: Colors.black87,
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => const HomePage(), 
        '/lyrics': (context) => const LyricsPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/lyrics') {
          final args = settings.arguments;
          if (args == null || args is! Map) {
            return _errorRoute();
          }
        }
        return null;
      },
    );
  }

  // Error Route
  MaterialPageRoute _errorRoute() { 
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: const Center(
          child: Text(
            'Failed to load song data.',
            style: TextStyle(color: Colors.red, fontSize: 18),
          ),
        ),
      ),
    );
  }
}
