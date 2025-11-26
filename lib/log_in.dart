import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:complete_music_player/main.dart';
import 'song_lyrics_display/navigation/home_page.dart';
import 'sign_up.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final CollectionReference users =
      FirebaseFirestore.instance.collection('users');

  bool _loading = false; // for username/password login

 Future<void> _login() async {
  setState(() => _loading = true);
  try {
    final snapshot = await users
        .where('username', isEqualTo: _usernameController.text)
        .where('password', isEqualTo: _passwordController.text)
        .get();

    if (snapshot.docs.isNotEmpty) {
      final doc = snapshot.docs.first;
      final userData = {
        'first_name': doc['first_name'],
        'last_name': doc['last_name'],
        'full_name': doc['full_name'],
        'email': doc['email'],
        'photo_url': doc['photo_url'] ?? '',
      };

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        CupertinoPageRoute(
          builder: (_) => HomePage(userData: userData), // Pass Firestore info
        ),
      );
    } else {
      _showError("Invalid username or password!");
    }
  } catch (e) {
    _showError("Login failed: $e");
  } finally {
    if (!mounted) return;
    setState(() => _loading = false);
  }
}


  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message, style: const TextStyle(color: Colors.white)),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: const Color(0xFF2E2626),
        elevation: 0,
        title: const Text(
          'Aexor',
          style: TextStyle(
            color: Color(0xFF1DB954),
            fontWeight: FontWeight.bold,
            fontSize: 30,
          ),
        ),
        centerTitle: true,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: _loginFields(),
            
          ),
        ),
      ),
    );
  }

  List<Widget> _loginFields() {
    return [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Color(0xFF1DB954)),
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  CupertinoPageRoute(builder: (_) => const MyApp()),
                  (route) => false,
                );
              },
            ),
            const SizedBox(width: 10),
            const Text(
              "Login",
              style: TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      const SizedBox(height: 30),
      TextField(
        controller: _usernameController,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration("Username"),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: _passwordController,
        obscureText: true,
        style: const TextStyle(color: Colors.white),
        decoration: _inputDecoration("Password"),
      ),
      const SizedBox(height: 40),

      // Login button with loading state
      _loading
          ? const CircularProgressIndicator(color: Color(0xFF1DB954))
          : SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _login,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1DB954),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                ),
                child: const Text(
                  'Log In',
                  style: TextStyle(
                      color: Colors.black,
                      fontSize: 18,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),

      const SizedBox(height: 20),

      // Sign-up redirect
      TextButton(
        onPressed: () {
          Navigator.of(context).push(
            CupertinoPageRoute(builder: (_) => const SignUpScreen()),
          );
        },
        child: const Text(
          "Don't have an account? Sign up",
          style: TextStyle(
            color: Color(0xFF1DB954),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    ];
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFFB3B3B3)),
      filled: true,
      fillColor: Colors.black,
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFB3B3B3)),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFF1DB954), width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }
}
