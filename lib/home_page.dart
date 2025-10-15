import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tabs/lost_items_page.dart';
import 'tabs/found_items_page.dart';
import 'tabs/post_item_page.dart';
import 'chats/chat_page.dart';
import 'tabs/profile_page.dart'; // NEW

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  final user = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    _tabController = TabController(length: 4, vsync: this);
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff7f9fa),
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.train, color: Colors.indigo[700]),
            const SizedBox(width: 10),
            Text(
              "Lost & Found Board",
              style: TextStyle(
                color: Colors.indigo[800],
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Chats',
            icon: const Icon(Icons.chat_bubble_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatsPage()),
              );
            },
          ),
          // Removed top-right logout button; logout will live in Profile tab
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: false,
          indicatorColor: Colors.indigo[700],
          tabs: const [
            Tab(
              icon: Icon(Icons.sentiment_dissatisfied, color: Colors.redAccent),
              text: "Lost",
              height: 48,
            ),
            Tab(
              icon: Icon(Icons.archive, color: Colors.green),
              text: "Found",
              height: 48,
            ),
            Tab(
              icon: Icon(Icons.add_circle, color: Colors.indigo),
              text: "Post New",
              height: 48,
            ),
            Tab(
              icon: Icon(Icons.person, color: Colors.blueGrey),
              text: "Profile",
              height: 48,
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          LostItemsPage(),
          FoundItemsPage(),
          PostItemPage(),
          ProfilePage(), // last tab now
        ],
      ),
    );
  }
}
