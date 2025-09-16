import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class ChatRepo {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String get uid => _auth.currentUser?.uid ?? '';

  String _nameFromEmail(String e) => e.isNotEmpty ? e.split('@').first : 'User';

  Future<String> startOrGetConversation({
    required String itemId,
    required String posterUid,
  }) async {
    final me = uid;
    if (me.isEmpty) throw Exception('Not signed in');

    // Try to find existing conversation for this item and pair
    final qs = await _db
        .collection('conversations')
        .where('participants', arrayContains: me)
        .where('itemId', isEqualTo: itemId)
        .limit(10)
        .get();

    for (final d in qs.docs) {
      final ps = List<String>.from(d['participants'] as List);
      if (ps.contains(posterUid)) {
        await _ensureParticipantNames(d.reference, me, posterUid, itemId: itemId);
        return d.id;
      }
    }

    // Friendly names
    final myEmail = _auth.currentUser?.email ?? '';
    final myName = _nameFromEmail(myEmail);

    // Prefer RTDB profile for poster
    String posterName = 'User';
    try {
      final rtdbSnap = await FirebaseDatabase.instance.ref('users/$posterUid').get();
      final map = (rtdbSnap.value is Map)
          ? Map<String, dynamic>.from(rtdbSnap.value as Map)
          : <String, dynamic>{};
      final rtdbName = (map['name'] ?? '').toString();
      final rtdbEmail = (map['email'] ?? '').toString();
      if (rtdbName.isNotEmpty) {
        posterName = rtdbName;
      } else if (rtdbEmail.isNotEmpty) {
        posterName = _nameFromEmail(rtdbEmail);
      } else {
        try {
          final itemDoc = await _db.collection('items').doc(itemId).get();
          final postedByEmail = (itemDoc.data()?['postedByEmail'] ?? '').toString();
          if (postedByEmail.isNotEmpty) {
            posterName = _nameFromEmail(postedByEmail);
          }
        } catch (_) {}
      }
    } catch (_) {
      try {
        final itemDoc = await _db.collection('items').doc(itemId).get();
        final postedByEmail = (itemDoc.data()?['postedByEmail'] ?? '').toString();
        if (postedByEmail.isNotEmpty) {
          posterName = _nameFromEmail(postedByEmail);
        }
      } catch (_) {}
    }

    final now = FieldValue.serverTimestamp();
    final doc = await _db.collection('conversations').add({
      'participants': [me, posterUid]..sort(),
      'itemId': itemId,
      'lastMessageText': '',
      'lastMessageAt': now,
      'createdAt': now,
      'typing': <String, bool>{},
      'participantMeta': {
        me: {'name': myName},
        posterUid: {'name': posterName},
      },
    });

    return doc.id;
  }

  // Backfill names for older threads (uses RTDB, falls back to itemId)
  Future<void> _ensureParticipantNames(
    DocumentReference convRef,
    String me,
    String otherUid, {
    String? itemId,
  }) async {
    try {
      final snap = await convRef.get();
      final data = snap.data() as Map<String, dynamic>? ?? {};
      final meta = (data['participantMeta'] as Map?)?.cast<String, dynamic>() ?? {};
      final hasMe = (meta[me]?['name'] ?? '').toString().isNotEmpty;
      final hasOther = (meta[otherUid]?['name'] ?? '').toString().isNotEmpty;
      if (hasMe && hasOther) return;

      final myEmail = _auth.currentUser?.email ?? '';
      final myName = _nameFromEmail(myEmail);

      String otherName = 'User';
      try {
        final s = await FirebaseDatabase.instance.ref('users/$otherUid').get();
        final m = (s.value is Map) ? Map<String, dynamic>.from(s.value as Map) : <String, dynamic>{};
        final n = (m['name'] ?? '').toString();
        final e = (m['email'] ?? '').toString();
        otherName = n.isNotEmpty ? n : _nameFromEmail(e);
      } catch (_) {
        if ((itemId ?? '').isNotEmpty) {
          try {
            final itemDoc = await _db.collection('items').doc(itemId).get();
            final postedByEmail = (itemDoc.data()?['postedByEmail'] ?? '').toString();
            if (postedByEmail.isNotEmpty) {
              otherName = _nameFromEmail(postedByEmail);
            }
          } catch (_) {}
        }
      }

      await convRef.set({
        'participantMeta': {
          me: {'name': myName},
          otherUid: {'name': otherName},
        }
      }, SetOptions(merge: true));
    } catch (_) {
      // best-effort backfill
    }
  }

  // Public helper for UI-triggered backfill
  Future<void> ensureParticipantNames({
    required String conversationId,
    required String myUid,
    required String otherUid,
    String? itemId,
  }) {
    return _ensureParticipantNames(
      _db.collection('conversations').doc(conversationId),
      myUid,
      otherUid,
      itemId: itemId,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> conversationList() {
    final me = uid;
    return _db
        .collection('conversations')
        .where('participants', arrayContains: me)
        .orderBy('lastMessageAt', descending: true)
        .snapshots();
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> messages(String cid, {int limit = 50}) {
    return _db
        .collection('conversations')
        .doc(cid)
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> conversation(String cid) {
    return _db.collection('conversations').doc(cid).snapshots();
  }

  Future<void> sendText(String cid, String text) async {
    final me = uid;
    final t = text.trim();
    if (t.isEmpty || me.isEmpty) return;

    final ref = _db.collection('conversations').doc(cid);
    final batch = _db.batch();
    final msgRef = ref.collection('messages').doc();

    batch.set(msgRef, {
      'senderUid': me,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': {me: true},
    });

    batch.update(ref, {
      'lastMessageText': t,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> sendImage(String cid, String imageUrl) async {
    final me = uid;
    if (imageUrl.isEmpty || me.isEmpty) return;

    final ref = _db.collection('conversations').doc(cid);
    final batch = _db.batch();
    final msgRef = ref.collection('messages').doc();

    batch.set(msgRef, {
      'senderUid': me,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': {me: true},
    });

    batch.update(ref, {
      'lastMessageText': '[Photo]',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  Future<void> markSeen(
    String cid,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) async {
    final me = uid;
    if (docs.isEmpty || me.isEmpty) return;

    final writes = <Future>[];
    for (final d in docs) {
      final data = d.data();
      final seenBy = Map<String, dynamic>.from(data['seenBy'] ?? {});
      if (seenBy[me] == true) continue;
      writes.add(d.reference.update({'seenBy.$me': true}));
    }
    await Future.wait(writes);
  }

  Future<void> setTyping(String cid, bool isTyping) async {
    final me = uid;
    if (me.isEmpty) return;
    final convRef = _db.collection('conversations').doc(cid);
    await convRef.set({'typing': {me: isTyping}}, SetOptions(merge: true));
  }

  // ===== Delete / Hide APIs =====

  // Hide chat for current user
  Future<void> hideChatForMe(String cid) async {
    final me = uid;
    if (me.isEmpty) return;
    await _db.collection('conversations').doc(cid).update({
      'deletedFor.$me': FieldValue.serverTimestamp(),
    });
  }

  // Delete a single message for current user
  Future<void> deleteMessageForMe(String cid, String mid) async {
    final me = uid;
    if (me.isEmpty) return;
    await _db.collection('conversations').doc(cid)
        .collection('messages').doc(mid).update({
      'deletedFor.$me': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  // Delete a single message for everyone (sender/admin)
  Future<void> deleteMessageForEveryone({
    required String cid,
    required String mid,
    required String senderUid,
  }) async {
    if (uid != senderUid) {
      throw Exception('Only sender can delete for everyone');
    }
    await _db.collection('conversations').doc(cid)
        .collection('messages').doc(mid).update({
      'deletedForEveryone': true,
      'hasTombstone': true,
      'tombstoneText': 'Message deleted',
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }
}
