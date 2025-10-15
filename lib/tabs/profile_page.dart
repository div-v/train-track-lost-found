import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'my_posts_page.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'Unknown';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    return Scaffold(
      backgroundColor: const Color(0xfff7f9fa),
      body: Column(
        children: [
          // Header
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.indigo[100],
                  child: Text(
                    initial,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.indigo),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    email,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),

          // Section title
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: const Text('My Posts', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          ),

          // Posts list fills remaining space
          const Expanded(child: MyPostsPage()),
        ],
      ),

      // Logout button fixed at bottom
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
          child: ElevatedButton.icon(
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).pushNamedAndRemoveUntil('/login', (r) => false);
              }
            },
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ),
    );
  }
}
