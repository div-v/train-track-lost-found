import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class MyPostsPage extends StatelessWidget {
  const MyPostsPage({super.key});
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Center(child: Text("Not logged in."));
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('items')
        .where('postedBy', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(
            child: Text(
              "Error loading your posts.",
              style: const TextStyle(color: Colors.red),
            ),
          );
        }
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snap.hasData || snap.data!.docs.isEmpty) {
          return const Center(
            child: Text("You haven't posted any items yet.", style: TextStyle(fontSize: 18)),
          );
        }

        final docs = snap.data!.docs;
        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final item = docs[i].data() as Map<String, dynamic>;
            final id = docs[i].id;
            return Card(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ListTile(
                leading: item['photoUrl'] != null && (item['photoUrl'] as String).isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(item['photoUrl'],
                        width: 50, height: 50, fit: BoxFit.cover))
                  : Icon(Icons.image, size: 44, color: Colors.grey[400]),
                title: Text(item['title'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Status: ${item['status'] ?? 'active'}"),
                    Text("Type: ${item['type'] ?? ''}"),
                    Text("Date: ${(item['date'] is Timestamp)
                      ? (item['date'] as Timestamp).toDate().toString().split(' ').first
                      : (item['date']??'-').toString().split('T').first}"),
                  ],
                ),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('Edit')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                  onSelected: (choice) async {
                    if (choice == 'delete') {
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (_) => AlertDialog(
                          title: const Text('Delete Post?'),
                          content: const Text('Are you sure you want to delete this post?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        try {
                          await FirebaseFirestore.instance.collection('items').doc(id).delete();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post deleted.')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Delete failed: $e')));
                          }
                        }
                      }
                    } else if (choice == 'edit') {
                      showDialog(
                        context: context,
                        builder: (_) => EditPostDialog(
                          docId: id,
                          data: item,
                        ),
                      );
                    }
                  },
                ),
              ),
            );
          }
        );
      },
    );
  }
}

class EditPostDialog extends StatefulWidget {
  final String docId;
  final Map<String, dynamic> data;
  const EditPostDialog({super.key, required this.docId, required this.data});

  @override
  State<EditPostDialog> createState() => _EditPostDialogState();
}

class _EditPostDialogState extends State<EditPostDialog> {
  late TextEditingController titleController;
  late TextEditingController descController;
  late TextEditingController stationTrainController;
  late String status;
  late String category;
  late String type;

  // NOTE: statusOptions updated to ['active', 'claimed']
  final statusOptions = ['active', 'claimed'];
  final categoryOptions = [
    'Wallet',
    'Electronics',
    'Bag',
    'Document',
    'Clothing',
    'Jewelry',
    'Other'
  ];
  final typeOptions = ['lost', 'found'];

  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    titleController = TextEditingController(text: widget.data['title']);
    descController = TextEditingController(text: widget.data['description']);
    stationTrainController = TextEditingController(text: widget.data['stationOrTrain']);
    // Always use .contains to prevent value-mismatch Dropdown error!
    status = statusOptions.contains(widget.data['status']) 
      ? widget.data['status'] 
      : statusOptions.first;
    category = categoryOptions.contains(widget.data['category'])
      ? widget.data['category']
      : categoryOptions.first;
    type = typeOptions.contains(widget.data['type'])
      ? widget.data['type']
      : typeOptions.first;
  }

  @override
  void dispose() {
    titleController.dispose();
    descController.dispose();
    stationTrainController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Edit Post", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 10),
              TextFormField(
                controller: titleController,
                decoration: const InputDecoration(labelText: "Title"),
                validator: (val) =>
                  val == null || val.trim().isEmpty ? "Title required" : null,
              ),
              TextFormField(
                controller: descController,
                decoration: const InputDecoration(labelText: "Description"),
                maxLines: 3,
                validator: (val) =>
                  val == null || val.trim().isEmpty ? "Description required" : null,
              ),
              TextFormField(
                controller: stationTrainController,
                decoration: const InputDecoration(labelText: "Station/Train"),
                validator: (val) =>
                  val == null || val.trim().isEmpty ? "Station/Train required" : null,
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: status,
                items: statusOptions
                    .map((s) => DropdownMenuItem(value: s, child: Text(s[0].toUpperCase() + s.substring(1))))
                    .toList(),
                decoration: const InputDecoration(labelText: "Status"),
                onChanged: (val) => setState(() => status = val ?? statusOptions.first),
              ),
              DropdownButtonFormField<String>(
                value: category,
                items: categoryOptions
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                decoration: const InputDecoration(labelText: "Category"),
                onChanged: (val) => setState(() => category = val ?? categoryOptions.first),
              ),
              DropdownButtonFormField<String>(
                value: type,
                items: typeOptions
                    .map((t) => DropdownMenuItem(value: t, child: Text(t[0].toUpperCase() + t.substring(1))))
                    .toList(),
                decoration: const InputDecoration(labelText: "Type"),
                onChanged: (val) => setState(() => type = val ?? typeOptions.first),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        if (!_formKey.currentState!.validate()) return;
                        try {
                          await FirebaseFirestore.instance.collection('items')
                            .doc(widget.docId)
                            .update({
                              'title': titleController.text.trim(),
                              'description': descController.text.trim(),
                              'stationOrTrain': stationTrainController.text.trim(),
                              'status': status,
                              'category': category,
                              'type': type,
                            });
                          if (context.mounted) {
                            Navigator.pop(context);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Post updated.')));
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Update failed: $e')));
                          }
                        }
                      },
                      child: const Text("Save"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                  ),
                ],
              )
            ],
          ),
        ),
      ),
    );
  }
}

