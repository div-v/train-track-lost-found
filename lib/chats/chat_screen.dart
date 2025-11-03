// lib/chat_screen.dart
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cloudinary_public/cloudinary_public.dart';
import 'chat_repo.dart';

class ChatScreen extends StatefulWidget {
  final String posterId; // from ItemCard
  final String posterName; // for title
  final String? itemId; // optional if you want to start here
  final String? conversationId; // allow direct open by cid too

  const ChatScreen({
    super.key,
    required this.posterId,
    required this.posterName,
    this.itemId,
    this.conversationId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _repo = ChatRepo();
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _picker = ImagePicker();

  String? _cid;
  Timer? _typingDebounce;

  @override
  void initState() {
    super.initState();

    if (widget.posterId.isEmpty || (widget.itemId == null && widget.conversationId == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid chat target')),
        );
        Navigator.pop(context);
      });
      return;
    }

    _initConversation();
    _textCtrl.addListener(_onTypingChanged);
  }

  @override
  void dispose() {
    _typingDebounce?.cancel();
    _textCtrl.removeListener(_onTypingChanged);
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initConversation() async {
    if (widget.conversationId != null) {
      setState(() => _cid = widget.conversationId);
      return;
    }
    final cid = await _repo.startOrGetConversation(
      itemId: widget.itemId ?? 'unknown_item',
      posterUid: widget.posterId,
    );
    if (mounted) setState(() => _cid = cid);
  }

  void _onTypingChanged() {
    if (_cid == null) return;
    _typingDebounce?.cancel();
    _repo.setTyping(_cid!, true);
    _typingDebounce = Timer(const Duration(milliseconds: 800), () {
      _repo.setTyping(_cid!, false);
    });
  }

  Future<void> _send() async {
    final txt = _textCtrl.text.trim();
    if (txt.isEmpty || _cid == null) return;
    await _repo.sendText(_cid!, txt);
    _textCtrl.clear();
    _repo.setTyping(_cid!, false);
  }

  Future<String> _uploadToCloudinary(String filePath) async {
    const cloudName = 'dm7npuvli';
    const uploadPreset = 'unsigned_upload';

    final cloudinary = CloudinaryPublic(cloudName, uploadPreset, cache: false);
    try {
      final res = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(filePath, resourceType: CloudinaryResourceType.Image),
      );
      return res.secureUrl;
    } on CloudinaryException catch (e) {
      throw Exception('Cloudinary upload failed: ${e.message}');
    }
  }

  Future<void> _pickImage(ImageSource src) async {
    if (_cid == null) return;
    final picked = await _picker.pickImage(source: src, imageQuality: 80, maxWidth: 1600);
    if (picked == null) return;

    final httpsUrl = await _uploadToCloudinary(picked.path);
    await _repo.sendImage(_cid!, httpsUrl);
  }

  Future<String?> _confirmDelete(BuildContext context, {required bool fromMe}) async {
    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Delete message?'),
          content: const Text('Choose how to delete this message.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop('delete_me'),
              child: const Text('Delete for me'),
            ),
            if (fromMe)
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('delete_all'),
                child: const Text('Delete for everyone'),
              ),
          ],
        );
      },
    );
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cid = _cid;
    final safeName = widget.posterName.isNotEmpty ? widget.posterName : 'User';
    final initial = safeName.isNotEmpty ? safeName[0].toUpperCase() : '?';

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            CircleAvatar(child: Text(initial)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(safeName, overflow: TextOverflow.ellipsis),
                  if (cid != null)
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _repo.conversation(cid),
                      builder: (_, snap) {
                        if (!snap.hasData) return const SizedBox.shrink();
                        final data = snap.data!.data() ?? {};
                        final typing = (data['typing'] is Map)
                            ? Map<String, dynamic>.from(data['typing'])
                            : const <String, dynamic>{};
                        final someoneTyping = typing.entries.any((e) => e.value == true);
                        return someoneTyping
                            ? const Text('typing…', style: TextStyle(fontSize: 12, color: Colors.white70))
                            : const SizedBox.shrink();
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: cid == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _repo.messages(cid),
                    builder: (_, snap) {
                      if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                      final msgs = snap.data!.docs;

                      // Filter out messages deleted for current user
                      final visibleMsgs = msgs.where((doc) {
                        final data = doc.data();
                        final deletedFor = (data['deletedFor'] is Map)
                            ? Map<String, dynamic>.from(data['deletedFor'])
                            : <String, dynamic>{};
                        return deletedFor[_repo.uid] != true;
                      }).toList();

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _repo.markSeen(cid, visibleMsgs);
                      });

                      if (visibleMsgs.isEmpty) return const Center(child: Text('Say hi 👋'));

                      return ListView.builder(
                        controller: _scrollCtrl,
                        reverse: true,
                        itemCount: visibleMsgs.length,
                        itemBuilder: (_, i) {
                          final doc = visibleMsgs[i];
                          final m = doc.data();
                          final fromMe = (m['senderUid'] ?? '') == _repo.uid;

                          final deletedForEveryone = (m['deletedForEveryone'] ?? false) == true;
                          final tombText = (m['tombstoneText'] ?? 'Message deleted') as String;

                          final String imageUrl = (m['imageUrl'] ?? '') as String;
                          final bool hasImage = imageUrl.isNotEmpty && !deletedForEveryone;

                          final String textRaw = (m['text'] ?? '') as String;
                          final String text = deletedForEveryone ? tombText : textRaw;

                          final bubbleColor = deletedForEveryone
                              ? Colors.grey.shade200
                              : (fromMe ? Colors.green : Colors.grey.shade300);
                          final textColor = deletedForEveryone
                              ? Colors.black54
                              : (fromMe ? Colors.white : Colors.black);

                          final isSeen = _isSeenByOther(m);

                          Widget? mediaWidget;
                          if (hasImage) {
                            mediaWidget = imageUrl.startsWith('file://')
                                ? Image.file(File(imageUrl.replaceFirst('file://', '')),
                                    width: 220, height: 220, fit: BoxFit.cover)
                                : Image.network(imageUrl, width: 220, height: 220, fit: BoxFit.cover);
                          }

                          return Align(
                            alignment: fromMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () async {
                                final choice = await _confirmDelete(context, fromMe: fromMe);
                                if (choice == 'delete_me') {
                                  await _repo.deleteMessageForMe(cid, doc.id);
                                  _toast('Message deleted for you');
                                } else if (choice == 'delete_all' && fromMe) {
                                  await _repo.deleteMessageForEveryone(
                                    cid: cid,
                                    mid: doc.id,
                                    senderUid: _repo.uid,
                                  );
                                  _toast('Message deleted for everyone');
                                }
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: bubbleColor,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    if (mediaWidget != null)
                                      ClipRRect(borderRadius: BorderRadius.circular(10), child: mediaWidget),
                                    if (text.isNotEmpty)
                                      Text(
                                        text,
                                        style: TextStyle(
                                          color: textColor,
                                          fontStyle: deletedForEveryone ? FontStyle.italic : FontStyle.normal,
                                        ),
                                      ),
                                    const SizedBox(height: 4),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _formatTime(m['createdAt']),
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: fromMe ? Colors.white70 : Colors.black54),
                                        ),
                                        if (fromMe && !deletedForEveryone) ...[
                                          const SizedBox(width: 6),
                                          Icon(
                                            isSeen ? Icons.done_all : Icons.done,
                                            size: 16,
                                            color: isSeen
                                                ? Colors.lightBlueAccent
                                                : (fromMe ? Colors.white70 : Colors.black45),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.photo_library),
                          onPressed: () => _pickImage(ImageSource.gallery),
                          tooltip: 'Gallery',
                        ),
                        IconButton(
                          icon: const Icon(Icons.photo_camera),
                          onPressed: () => _pickImage(ImageSource.camera),
                          tooltip: 'Camera',
                        ),
                        Expanded(
                          child: TextField(
                            controller: _textCtrl,
                            decoration: const InputDecoration(
                              hintText: 'Message',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            minLines: 1,
                            maxLines: 5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        CircleAvatar(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          child: IconButton(
                            icon: const Icon(Icons.send, color: Colors.white),
                            onPressed: _send,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  bool _isSeenByOther(Map<String, dynamic> m) {
    final seenBy = (m['seenBy'] is Map)
        ? Map<String, dynamic>.from(m['seenBy'])
        : const <String, dynamic>{};
    if (seenBy.isEmpty) return false;
    return seenBy.entries.any((e) => e.key != _repo.uid && e.value == true);
  }

  String _formatTime(dynamic ts) {
    if (ts is Timestamp) {
      final d = ts.toDate();
      final hh = d.hour.toString().padLeft(2, '0');
      final mm = d.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return '';
  }
}
