import 'dart:async';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:flutter/material.dart';
import 'suggestionItem.dart';
import 'railradar_client.dart';

class StationTrainAutocompleteField extends StatefulWidget {
  final Function(String) onChanged;
  final String? initialValue;
  final String apiKey; // RailRadar API key injected by caller

  const StationTrainAutocompleteField({
    super.key,
    required this.onChanged,
    required this.apiKey,
    this.initialValue,
  });

  @override
  State<StationTrainAutocompleteField> createState() => _StationTrainAutocompleteFieldState();
}

class _StationTrainAutocompleteFieldState extends State<StationTrainAutocompleteField> {
  final TextEditingController _controller = TextEditingController();
  late final RailRadarRepository repo;
  bool _warmed = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      _controller.text = widget.initialValue!;
    }
    repo = RailRadarRepository(RailRadarClient(apiKey: widget.apiKey));
    _warmAll();
  }

  Future<void> _warmAll() async {
    try {
      await repo.warmAll();
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _warmed = true);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<List<SuggestionItem>> _query(String q) async {
    final qn = q.trim();
    if (qn.length < 2) return const [];
    // Local-only filter ensures suggestions even if search endpoint rejects input
    final local = _warmed ? repo.filter(qn) : <SuggestionItem>[];
    return local.take(25).toList();
  }

  @override
  Widget build(BuildContext context) {
    return TypeAheadFormField<SuggestionItem>(
      suggestionsBoxDecoration: const SuggestionsBoxDecoration(
        elevation: 6,
        constraints: BoxConstraints(maxHeight: 260),
      ),
      textFieldConfiguration: TextFieldConfiguration(
        controller: _controller,
        decoration: InputDecoration(
          labelText: 'Station or Train (name or no)',
          prefixIcon: const Icon(Icons.train),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE0E3E7)),
          ),
        ),
      ),
      loadingBuilder: (context) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Loading...', style: TextStyle(color: Colors.grey)),
      ),
      noItemsFoundBuilder: (context) => const Padding(
        padding: EdgeInsets.all(12),
        child: Text('No items found', style: TextStyle(color: Colors.grey)),
      ),
      suggestionsCallback: (pattern) async {
        _debounce?.cancel();
        final completer = Completer<List<SuggestionItem>>();
        _debounce = Timer(const Duration(milliseconds: 220), () async {
          try {
            final res = await _query(pattern);
            completer.complete(res);
          } catch (_) {
            completer.complete(const []);
          }
        });
        return completer.future;
      },
      itemBuilder: (context, suggestion) {
        return ListTile(
          leading: Icon(
            suggestion.type == 'station' ? Icons.location_on : Icons.train,
            color: suggestion.type == 'station' ? Colors.blue : Colors.green,
          ),
          title: Text('${suggestion.codeOrNumber} - ${suggestion.name}'),
          subtitle: Text(suggestion.type.toUpperCase()),
        );
      },
      onSuggestionSelected: (suggestion) {
        final value = '${suggestion.codeOrNumber} - ${suggestion.name}';
        _controller.text = value;
        widget.onChanged(value);
      },
      validator: (val) {
        if (val == null || val.trim().isEmpty) {
          return 'Please select a station or train';
        }
        return null;
      },
    );
  }
}
