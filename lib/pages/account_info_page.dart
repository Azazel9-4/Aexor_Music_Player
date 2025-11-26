import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart'; 
import 'dart:ui';

class AccountInfoPage extends StatelessWidget {
  final Map<String, dynamic>? userData;
  const AccountInfoPage({super.key, this.userData});

  @override
  Widget build(BuildContext context) {
    final name = userData?['full_name'] ?? FirebaseAuth.instance.currentUser?.displayName ?? "Unknown User";
    final email = userData?['email'] ?? FirebaseAuth.instance.currentUser?.email ?? "No email";
    final photo = userData?['photo_url'] ?? FirebaseAuth.instance.currentUser?.photoURL;

    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
          ),
        ),
        Center(
          child: SingleChildScrollView(
            child: Container(
              width: 300,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF222222),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: const Icon(Icons.close, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 15),
                  CircleAvatar(
                    radius: 40,
                    backgroundImage: photo != null && photo.isNotEmpty
                        ? NetworkImage(photo)
                        : null,
                    child: photo == null || photo.isEmpty
                        ? const Icon(Icons.person, size: 40)
                        : null,
                  ),
                  const SizedBox(height: 15),
                  Text(
                    name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    email,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      color: Colors.white70,
                      decoration: TextDecoration.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
