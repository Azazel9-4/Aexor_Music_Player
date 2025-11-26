import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../song_lyrics_display/navigation/home_page.dart';

class OtpVerificationPage extends StatefulWidget {
  final String email;
  final String otp;
  final String userId; // add userId

  const OtpVerificationPage({
    super.key,
    required this.email,
    required this.otp,
    required this.userId,
  });

  @override
  State<OtpVerificationPage> createState() => _OtpVerificationPageState();
}

class _OtpVerificationPageState extends State<OtpVerificationPage> {
  final _codeController = TextEditingController();
  bool _verifying = false;

  Future<void> _verifyOtp() async {
    if (_codeController.text != widget.otp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Invalid OTP"),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _verifying = true);

    // Mark user as verified in Firestore
    await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .update({'isVerified': true});

    setState(() => _verifying = false);

    // Navigate to HomePage
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomePage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, color: Colors.green, size: 70),
            const SizedBox(height: 20),
            Text(
              "Enter OTP sent to\n${widget.email}",
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 25),
            TextField(
              controller: _codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24),
              decoration: const InputDecoration(
                counterText: "",
                hintText: "",
                hintStyle: TextStyle(color: Colors.grey, fontSize: 24),
                enabledBorder:
                    UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                focusedBorder:
                    UnderlineInputBorder(borderSide: BorderSide(color: Colors.green)),
              ),
            ),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: _verifying ? null : _verifyOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                minimumSize: const Size(double.infinity, 50),
              ),
              child: _verifying
                  ? const CircularProgressIndicator(color: Colors.black)
                  : const Text(
                      "Verify",
                      style: TextStyle(color: Colors.black, fontSize: 18),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
