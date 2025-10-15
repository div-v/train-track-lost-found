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

    final myEmail = _auth.currentUser?.email ?? '';
    final myName = _nameFromEmail(myEmail);

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
    } catch (_) {}
  }

  Future<void> ensureParticipantNames({
    required String conversationId,
    required String myUid,
    required String otherUid,
    String? itemId,
  }) =>
      _ensureParticipantNames(
        _db.collection('conversations').doc(conversationId),
        myUid,
        otherUid,
        itemId: itemId,
      );

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

  List<QueryDocumentSnapshot<Map<String, dynamic>>> filterVisibleForMe(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final me = uid;
    return snap.docs.where((d) {
      final data = d.data();
      final df = (data['deletedFor'] as Map?)?.cast<String, dynamic>();
      final hidden = df != null && df[me] == true;
      return !hidden;
    }).toList();
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> conversation(String cid) {
    return _db.collection('conversations').doc(cid).snapshots();
  }

  // ------------- Per-user "last visible" helpers -------------

  Future<List<String>> _getParticipants(String cid) async {
    final conv = await _db.collection('conversations').doc(cid).get();
    return List<String>.from((conv.data()?['participants'] ?? const []) as List);
  }

  Future<void> _setLastBy(
    String cid, {
    required Map<String, String> textBy,
    required Map<String, Timestamp?> atBy,
    String? globalText,
    Timestamp? globalAt,
  }) async {
    final convRef = _db.collection('conversations').doc(cid);
    final updates = <String, dynamic>{};
    textBy.forEach((k, v) => updates['lastMessageTextBy.$k'] = v);
    atBy.forEach((k, v) => updates['lastMessageAtBy.$k'] = v);
    if (globalText != null) updates['lastMessageText'] = globalText;
    if (globalAt != null) updates['lastMessageAt'] = globalAt;
    await convRef.set(updates, SetOptions(merge: true));
  }

  Future<Map<String, dynamic>?> _findLatestVisibleFor(String cid, String viewerUid) async {
    final convRef = _db.collection('conversations').doc(cid);
    final qs = await convRef
        .collection('messages')
        .orderBy('createdAt', descending: true)
        .limit(25)
        .get();
    for (final d in qs.docs) {
      final m = d.data();
      final df = (m['deletedFor'] is Map) ? Map<String, dynamic>.from(m['deletedFor']) : const <String, dynamic>{};
      final deletedForEveryone = (m['deletedForEveryone'] ?? false) == true;
      if (df[viewerUid] == true) continue;
      final text = deletedForEveryone ? (m['tombstoneText'] ?? 'Message deleted') : (m['text'] ?? '');
      return {'text': text as String, 'createdAt': m['createdAt'] as Timestamp?};
    }
    return null;
  }

  Future<void> _updateLastForUsersAfterSend({
    required String cid,
    required String textOrPhoto,
    required Timestamp? createdAt,
    required List<String> participants,
  }) async {
    final byText = <String, String>{ for (final p in participants) p: textOrPhoto };
    final byAt = <String, Timestamp?>{ for (final p in participants) p: createdAt };
    await _setLastBy(cid, textBy: byText, atBy: byAt, globalText: textOrPhoto, globalAt: createdAt);
  }

  Future<void> _updateLastForEveryoneDelete({
    required String cid,
    required String tombstoneText,
    required Timestamp? at,
    required List<String> participants,
  }) async {
    final byText = <String, String>{ for (final p in participants) p: tombstoneText };
    final byAt = <String, Timestamp?>{ for (final p in participants) p: at };
    await _setLastBy(cid, textBy: byText, atBy: byAt, globalText: tombstoneText, globalAt: at);
  }

  Future<void> _updateLastForMeAfterDelete({
    required String cid,
    required String me,
  }) async {
    final latest = await _findLatestVisibleFor(cid, me);
    final text = (latest?['text'] as String?) ?? '';
    final at = latest?['createdAt'] as Timestamp?;
    await _setLastBy(cid, textBy: {me: text}, atBy: {me: at});
  }

  // ---------------- Message actions ----------------

  Future<void> sendText(String cid, String text) async {
    final me = uid;
    final t = text.trim();
    if (t.isEmpty || me.isEmpty) return;

    final convRef = _db.collection('conversations').doc(cid);
    final msgRef = convRef.collection('messages').doc();
    final batch = _db.batch();

    batch.set(msgRef, {
      'senderUid': me,
      'text': t,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': {me: true},
    });

    batch.update(convRef, {
      'lastMessageText': t,
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    final parts = await _getParticipants(cid);
    final createdAtSnap = await msgRef.get();
    final ts = createdAtSnap.data()?['createdAt'] as Timestamp?;
    await _updateLastForUsersAfterSend(
      cid: cid,
      textOrPhoto: t,
      createdAt: ts,
      participants: parts,
    );
  }

  Future<void> sendImage(String cid, String imageUrl) async {
    final me = uid;
    if (imageUrl.isEmpty || me.isEmpty) return;

    final convRef = _db.collection('conversations').doc(cid);
    final msgRef = convRef.collection('messages').doc();
    final batch = _db.batch();

    batch.set(msgRef, {
      'senderUid': me,
      'imageUrl': imageUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'seenBy': {me: true},
    });

    batch.update(convRef, {
      'lastMessageText': '[Photo]',
      'lastMessageAt': FieldValue.serverTimestamp(),
    });

    await batch.commit();

    final parts = await _getParticipants(cid);
    final ts = (await msgRef.get()).data()?['createdAt'] as Timestamp?;
    await _updateLastForUsersAfterSend(
      cid: cid,
      textOrPhoto: '[Photo]',
      createdAt: ts,
      participants: parts,
    );
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

  Future<void> hideChatForMe(String cid) async {
    final me = uid;
    if (me.isEmpty) return;
    await _db.collection('conversations').doc(cid).update({
      'deletedFor.$me': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteMessageForMe(String cid, String mid) async {
    final me = uid;
    if (me.isEmpty) return;

    final convSnap = await _db.collection('conversations').doc(cid).get();
    final parts = List<String>.from((convSnap.data()?['participants'] ?? const []) as List);
    if (!parts.contains(me)) {
      throw Exception('Not a participant for this conversation');
    }

    final ref = _db.collection('conversations').doc(cid).collection('messages').doc(mid);

    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) return;

      final data = snap.data() as Map<String, dynamic>? ?? {};
      final existing = (data['deletedFor'] is Map)
          ? Map<String, dynamic>.from(data['deletedFor'])
          : const <String, dynamic>{};

      if (existing[me] == true) return;

      tx.update(ref, {
        'deletedFor.$me': true,
        'deletedAt': FieldValue.serverTimestamp(),
      });
    });

    await _updateLastForMeAfterDelete(cid: cid, me: me);
  }

  Future<void> deleteMessageForEveryone({
    required String cid,
    required String mid,
    required String senderUid,
  }) async {
    if (uid != senderUid) {
      throw Exception('Only sender can delete for everyone');
    }
    final msgRef = _db
        .collection('conversations')
        .doc(cid)
        .collection('messages')
        .doc(mid);

    await msgRef.update({
      'deletedForEveryone': true,
      'hasTombstone': true,
      'tombstoneText': 'Message deleted',
      'deletedAt': FieldValue.serverTimestamp(),
    });

    final parts = await _getParticipants(cid);
    final ts = (await msgRef.get()).data()?['createdAt'] as Timestamp?;
    await _updateLastForEveryoneDelete(
      cid: cid,
      tombstoneText: 'Message deleted',
      at: ts,
      participants: parts,
    );
  }
}
