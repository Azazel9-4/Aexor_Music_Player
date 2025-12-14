import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class HelpSupportPage extends StatelessWidget {
  const HelpSupportPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text("Help & Support"),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          //---------------- Contact Support ----------------//
          ListTile(
            leading: const Icon(Icons.email_outlined, color: Colors.white),
            title: const Text("Contact Support", style: TextStyle(color: Colors.white)),
            onTap: _contactSupport,
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 16),

          //---------------- Privacy ----------------//
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined, color: Colors.white),
            title: const Text("Privacy Policy", style: TextStyle(color: Colors.white)),
            onTap: () => _openUrl("https://docs.google.com/document/d/180poj-v9DHj543l6d_wwt-ncKy2BRbqKtfNSfmrm5AY/edit?usp=sharing"),
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          const SizedBox(height: 16),

          //---------------- Terms ----------------//
          ListTile(
            leading: const Icon(Icons.article_outlined, color: Colors.white),
            title: const Text("Terms of Service", style: TextStyle(color: Colors.white)),
            onTap: () => _openUrl("https://docs.google.com/document/d/15kiO9dOM5Ls6yGEYzFy3sk4lfmuGdzQzw1wYEO4ewMg/edit?usp=sharing"),
            tileColor: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ],
      ),
    );
  }


  static void _openUrl(String link) async {
    final url = Uri.parse(link);
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint("Could not launch URL: $e");
    }
  }

  static void _contactSupport() async {
    final email = Uri(
      scheme: 'mailto',
      path: 'prowidget09@gmail.com',  // Your support email
      query: 'subject=Aexor Music Support&body=Describe your issue here:',
    );
    try {
      await launchUrl(email);
    } catch (e) {
      debugPrint("Could not open email client: $e");
    }
  }
}
