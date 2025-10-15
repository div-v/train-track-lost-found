import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'chat_screen.dart';
import 'chat_repo.dart';

class ChatsPage extends StatelessWidget {
  const ChatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        body: Center(child: Text('Sign in to see chats')),
      );
    }

    final q = FirebaseFirestore.instance
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .orderBy('lastMessageAt', descending: true);

    return Scaffold(
      appBar: AppBar(title: const Text('Chats')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: q.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final all = snap.data?.docs ?? [];

          // Exclude conversations hidden for me
          final docs = all.where((d) {
            final data = d.data();
            final del = (data['deletedFor'] is Map)
                ? Map<String, dynamic>.from(data['deletedFor'])
                : const <String, dynamic>{};
            return del[uid] != true;
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('No conversations yet'));
          }

          return ListView.builder(
            itemCount: docs.length,
            itemBuilder: (_, i) {
              final d = docs[i];
              final data = d.data();

              // Participants
              final parts = (data['participants'] is List)
                  ? List<String>.from(data['participants'] as List)
                  : <String>[];
              final otherUid = parts.firstWhere((p) => p != uid, orElse: () => '');

              // Friendly name
              final friendly = (data['participantMeta'] is Map &&
                      (data['participantMeta'][otherUid]?['name'] ?? '') != '')
                  ? data['participantMeta'][otherUid]['name'].toString()
                  : 'User';
              final initial = friendly.isNotEmpty ? friendly.characters.first : '?';

              // Backfill names for legacy conversations if missing
              if (friendly == 'User' && otherUid.isNotEmpty) {
                ChatRepo().ensureParticipantNames(
                  conversationId: d.id,
                  myUid: uid,
                  otherUid: otherUid,
                  itemId: (data['itemId'] ?? '').toString(),
                );
              }

              // Read per-user last text/time by flattened field path
              final myKey = 'lastMessageTextBy.$uid';
              final myAtKey = 'lastMessageAtBy.$uid';

              final rawText = data[myKey];
              final rawAt = data[myAtKey];

              final hasPerUser = rawText != null;
              String lastTextForMe = (rawText is String) ? rawText : '';
              Timestamp? lastAtForMe = (rawAt is Timestamp) ? rawAt : null;

              // Fallback only if no per-user entry exists
              if (!hasPerUser) {
                final del = (data['deletedFor'] is Map)
                    ? Map<String, dynamic>.from(data['deletedFor'])
                    : const <String, dynamic>{};
                final globalLast = (data['lastMessageText'] ?? '').toString();
                lastTextForMe = del[uid] == true ? '' : globalLast;
                lastAtForMe ??= data['lastMessageAt'] as Timestamp?;
              }

              final subtitle = hasPerUser
                  ? (lastTextForMe.isNotEmpty ? lastTextForMe : 'Photo')
                  : (lastTextForMe.isNotEmpty ? lastTextForMe : 'Photo');

              String time = '';
              if (lastAtForMe is Timestamp) {
                final dt = lastAtForMe.toDate();
                time = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
              }

              return ListTile(
                leading: CircleAvatar(child: Text(initial)),
                title: Text(
                  friendly.isNotEmpty ? friendly : 'User',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatScreen(
                        posterId: otherUid,
                        posterName: friendly.isNotEmpty ? friendly : 'User',
                        conversationId: d.id,
                        itemId: (data['itemId'] ?? '').toString(),
                      ),
                    ),
                  );
                },
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(time),
                    PopupMenuButton<String>(
                      onSelected: (v) async {
                        if (v == 'delete_chat') {
                          await ChatRepo().hideChatForMe(d.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Chat hidden')),
                            );
                          }
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'delete_chat', child: Text('Delete chat')),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
