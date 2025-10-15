import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:traintrack_lost_found/chats/chat_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FoundItemsPage extends StatefulWidget {
  const FoundItemsPage({super.key});
  @override
  State<FoundItemsPage> createState() => _FoundItemsPageState();
}

class _FoundItemsPageState extends State<FoundItemsPage> {
  String search = '';
  String category = 'All';
  final categories = [
    'All',
    'Wallet',
    'Electronics',
    'Bag',
    'Document',
    'Clothing',
    'Jewelry',
    'Other',
  ];

  @override
  Widget build(BuildContext context) {
    final query = FirebaseFirestore.instance
        .collection('items')
        .where('type', isEqualTo: 'found')
        .orderBy('timestamp', descending: true);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: "Search found items, train/station...",
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            onChanged: (v) => setState(() => search = v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: categories
                .map(
                  (c) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: ChoiceChip(
                      label: Text(c),
                      selected: category == c,
                      onSelected: (sel) => setState(() => category = c),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: query.snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              var docs = snap.data!.docs
                  .map((d) => {'id': d.id, ...d.data() as Map<String, dynamic>})
                  .toList();
              if (search.isNotEmpty) {
                docs = docs.where((item) {
                  final s = search.toLowerCase();
                  return (item['title'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(s) ||
                      (item['description'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(s) ||
                      (item['stationOrTrain'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(s);
                }).toList();
              }
              if (category != 'All') {
                docs = docs
                    .where((item) => item['category'] == category)
                    .toList();
              }
              if (docs.isEmpty) {
                return const Center(child: Text('No found items yet.'));
              }
              return ListView.builder(
                itemCount: docs.length,
                itemBuilder: (_, i) =>
                    ItemCard(item: docs[i], itemType: "found"),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ----- ExpandableText Widget -----
class ExpandableText extends StatefulWidget {
  final String text;
  final int trimLength;
  const ExpandableText(this.text, {this.trimLength = 120, super.key});

  @override
  State<ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<ExpandableText> {
  bool expanded = false;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.length <= widget.trimLength) {
      return Text(text, style: const TextStyle(fontSize: 15));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          expanded ? text : '${text.substring(0, widget.trimLength)}...',
          style: const TextStyle(fontSize: 15),
          maxLines: expanded ? null : 4,
        ),
        GestureDetector(
          onTap: () => setState(() => expanded = !expanded),
          child: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              expanded ? "Show less" : "View details",
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Full image popup dialog function ---
void showPopupImageDialog(BuildContext context, String photoUrl) {
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (_) => Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.5,
              maxScale: 4.0,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: 350,
                  maxHeight: 350,
                ),
                child: Image.network(photoUrl, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(height: 10),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    ),
  );
}

// ----- ItemCard Widget (Updated with Chat Button) -----
class ItemCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final String itemType;
  const ItemCard({super.key, required this.item, required this.itemType});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: item['photoUrl'] != null && (item['photoUrl']).isNotEmpty
                  ? () => showPopupImageDialog(context, item['photoUrl'])
                  : null,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: item['photoUrl'] != null && (item['photoUrl']).isNotEmpty
                    ? Image.network(
                        item['photoUrl'],
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: double.infinity,
                        height: 180,
                        color: Colors.grey,
                        child: Icon(Icons.image, size: 60, color: Colors.grey),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item['title'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ExpandableText(item['description'] ?? '', trimLength: 120),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Text(
                        "Train/Station: ${item['stationOrTrain']}",
                        style: const TextStyle(color: Colors.black87),
                      ),
                      const Spacer(),
                      Text(
                        item['date'] is Timestamp
                            ? (item['date'] as Timestamp)
                                .toDate()
                                .toString()
                                .split(' ')
                                .first
                            : (item['date'] ?? '-').toString().split('T').first,
                        style: const TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.email),
                      label: const Text("Contact Poster"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () async {
                        final email = item['postedByEmail'];
                        final subject = Uri.encodeComponent(
                          'Regarding $itemType item: ${item['title']}',
                        );
                        final url = 'mailto:$email?subject=$subject';
                        if (await canLaunchUrl(Uri.parse(url))) {
                          await launchUrl(Uri.parse(url));
                        } else {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not launch email app.'),
                              ),
                            );
                          }
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.chat),
                      label: const Text("Chat with Poster"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () {
                        final me = FirebaseAuth.instance.currentUser?.uid ?? '';
                        final posterId =
                            (item['postedByUid'] ?? item['postedBy'] ?? '')
                                as String;

                        // Friendly name from email prefix (no UID exposed)
                        final email = (item['postedByEmail'] ?? '') as String;
                        final posterName = email.isNotEmpty
                            ? email.split('@').first
                            : 'User';

                        final itemId =
                            (item['id'] ?? item['docId'] ?? '') as String;

                        if (posterId.isEmpty || itemId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Missing poster or item info for chat',
                              ),
                            ),
                          );
                          return;
                        }

                        if (me.isNotEmpty && me == posterId) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Cannot message yourself"),
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ChatScreen(
                              posterId: posterId,
                              posterName: posterName,
                              itemId: itemId,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
