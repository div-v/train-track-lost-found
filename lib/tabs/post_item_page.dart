import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:cloudinary_public/cloudinary_public.dart';

class PostItemPage extends StatefulWidget {
  const PostItemPage({super.key});
  @override
  State<PostItemPage> createState() => _PostItemPageState();
}

class _PostItemPageState extends State<PostItemPage> {
  final _formKey = GlobalKey<FormState>();
  String _type = 'lost';
  String _title = '';
  String _desc = '';
  String _category = '';
  String _stationOrTrain = '';
  DateTime? _date;
  File? _imageFile;
  bool _loading = false;

  final List<String> _categories = [
    'Wallet', 'Electronics', 'Bag', 'Document', 'Clothing', 'Jewelry', 'Other'
  ];

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75);
    if (picked != null) setState(() { _imageFile = File(picked.path); });
  }

  Future<String?> _uploadImageToCloudinary(File imageFile) async {
    final cloudinary = CloudinaryPublic(
      'dm7npuvli',
      'unsigned_upload',
      cache: false,
    );
    try {
      final response = await cloudinary.uploadFile(
        CloudinaryFile.fromFile(
          imageFile.path,
          resourceType: CloudinaryResourceType.Image,
        ),
      );
      return response.secureUrl;
    } on CloudinaryException catch (e) {
      print('Cloudinary upload error: ${e.message}');
      return null;
    }
  }

  String _norm(String s) => s.trim().toLowerCase();

  Future<void> _onSubmit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please pick the date.'), backgroundColor: Colors.red));
      return;
    }
    if (_imageFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload a photo.'), backgroundColor: Colors.red));
      return;
    }

    setState(() => _loading = true);
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) throw Exception("Not logged in!");

      final photoUrl = await _uploadImageToCloudinary(_imageFile!);
      if (photoUrl == null) throw Exception('Image upload failed');

      final categoryNorm = _norm(_category);
      final titleNorm = _norm(_title);
      final stationNorm = _norm(_stationOrTrain);
      final dateOnlyStr = _date!.toUtc().toIso8601String().split('T').first;

      await FirebaseFirestore.instance.collection('items').add({
        'type': _type,
        'title': _title.trim(),
        'description': _desc.trim(),
        'category': _category,
        'stationOrTrain': _stationOrTrain.trim(),
        'date': Timestamp.fromDate(_date!),
        'photoUrl': photoUrl,
        'postedBy': user.uid,
        'postedByEmail': user.email,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'active',
        'category_norm': categoryNorm,
        'title_norm': titleNorm,
        'stationOrTrain_norm': stationNorm,
        'date_str_norm': dateOnlyStr,
      });

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          icon: const Icon(Icons.check_circle, color: Colors.green, size: 44),
          title: const Text("Posted!"),
          content: const Text("Your item has been reported successfully."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                setState(() {
                  _formKey.currentState?.reset();
                  _imageFile = null;
                  _type = 'lost';
                  _category = '';
                  _date = null;
                  _stationOrTrain = '';
                  _title = '';
                  _desc = '';
                });
              },
              child: const Text("OK"),
            )
          ],
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post: $e'), backgroundColor: Colors.red));
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: _loading,
      child: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Card(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              margin: const EdgeInsets.symmetric(vertical: 18),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text("Report Lost/Found Item",
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.indigo[800])),
                      const SizedBox(height: 14),
                      ToggleButtons(
                        isSelected: [_type == 'lost', _type == 'found'],
                        borderRadius: BorderRadius.circular(14),
                        selectedColor: Colors.white,
                        fillColor: Colors.indigo,
                        children: const [Text("Lost"), Text("Found")],
                        onPressed: (idx) => setState(() => _type = idx == 0 ? 'lost' : 'found'),
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        decoration: const InputDecoration(labelText: "Title", prefixIcon: Icon(Icons.title)),
                        maxLength: 40,
                        validator: (v) => v == null || v.trim().isEmpty ? "Title is required" : null,
                        onChanged: (v) => _title = v,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        decoration: const InputDecoration(labelText: "Description", prefixIcon: Icon(Icons.description)),
                        maxLines: 2,
                        maxLength: 120,
                        validator: (v) => v == null || v.trim().isEmpty ? "Description is required" : null,
                        onChanged: (v) => _desc = v,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _category.isNotEmpty ? _category : null,
                        items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                        decoration: const InputDecoration(labelText: "Category", prefixIcon: Icon(Icons.category)),
                        onChanged: (v) => setState(() => _category = v ?? ""),
                        validator: (v) => (v == null || v.isEmpty) ? "Please select a category" : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        decoration: const InputDecoration(labelText: "Station or Train Number", prefixIcon: Icon(Icons.train)),
                        validator: (v) => v == null || v.trim().isEmpty ? "Station or Train Number is required" : null,
                        onChanged: (v) => _stationOrTrain = v,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.date_range, color: Colors.blueGrey),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _date != null
                                  ? "Date: ${_date!.toLocal().toString().split(' ')[0]}"
                                  : "Select date",
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: DateTime.now(),
                                firstDate: DateTime.now().subtract(const Duration(days: 60)),
                                lastDate: DateTime.now().add(const Duration(days: 2)),
                              );
                              if (picked != null) setState(() => _date = picked);
                            },
                            child: const Text("Pick Date"),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickImage,
                        child: _imageFile == null
                            ? DottedBorder(
                                color: Colors.indigo,
                                borderType: BorderType.RRect,
                                radius: const Radius.circular(16),
                                strokeWidth: 1.8,
                                dashPattern: const [7, 4],
                                child: Container(
                                  height: 110,
                                  width: double.infinity,
                                  alignment: Alignment.center,
                                  child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.image, size: 36, color: Colors.blueGrey[300]),
                                        const SizedBox(height: 4),
                                        const Text("Tap to upload photo (required)"),
                                      ]),
                                ),
                              )
                            : ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.file(_imageFile!, width: double.infinity, height: 120, fit: BoxFit.cover),
                              ),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _onSubmit,
                        icon: const Icon(Icons.send),
                        label: const Text("Submit"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.indigo,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 17),
                          child: Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
