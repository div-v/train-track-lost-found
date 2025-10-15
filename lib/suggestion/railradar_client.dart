import 'dart:convert';
import 'package:http/http.dart' as http;

class RailRadarClient {
  final String apiKey;
  final String base;
  const RailRadarClient({
    required this.apiKey,
    this.base = 'https://railradar.in/api/v1',
  });

  // RailRadar expects capitalized header name.
  Map<String, String> get _headers => {
    'X-API-Key': apiKey,
    'Accept': 'application/json',
  };

  Future<List<List>> _fetchPairs(String path, String tag) async {
    final uri = Uri.parse('$base$path');
    final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    // Diagnostics (remove or switch to debugPrint in prod)
    // ignore: avoid_print
    print('[$tag] status=${r.statusCode} ct=${r.headers['content-type']} len=${r.body.length}');
    if (r.statusCode != 200) {
      // ignore: avoid_print
      print('[$tag] head=${r.body.substring(0, r.body.length > 240 ? 240 : r.body.length)}');
      throw Exception('$tag failed: ${r.statusCode}');
    }
    final body = jsonDecode(r.body);
    if (body is List) return body.whereType<List>().toList();
    if (body is Map && body['data'] is List) return (body['data'] as List).whereType<List>().toList();
    return const [];
  }

  // Stations: [["NDLS","NDLS - New Delhi"], ...]
  Future<List<List>> fetchAllStationsKvs() => _fetchPairs('/stations/all-kvs', 'STN-KVS');

  // Trains: [["12951","12951 - Rajdhani Express"], ...]
  Future<List<List>> fetchAllTrainsKvs() => _fetchPairs('/trains/all-kvs', 'TRN-KVS');

  // Optional: search trains by name/number; keep only after KVS works
  Future<List<Map<String, dynamic>>> searchTrains(String q, {int limit = 25}) async {
    final uri = Uri.parse('$base/trains/search?q=${Uri.encodeQueryComponent(q)}&limit=$limit');
    final r = await http.get(uri, headers: _headers).timeout(const Duration(seconds: 20));
    // ignore: avoid_print
    print('[TRN-SEARCH] status=${r.statusCode} ct=${r.headers['content-type']} len=${r.body.length}');
    if (r.statusCode != 200) {
      // ignore: avoid_print
      print('[TRN-SEARCH] head=${r.body.substring(0, r.body.length > 240 ? 240 : r.body.length)}');
      throw Exception('Trains search failed: ${r.statusCode}');
    }
    final body = jsonDecode(r.body);
    final List raw = body is List
        ? body
        : (body is Map && body['trains'] is List ? body['trains'] as List : const []);
    final List<Map<String, dynamic>> result = [];
    for (final e in raw) {
      if (e is Map) {
        final m = <String, dynamic>{};
        e.forEach((k, v) => m[k.toString()] = v);
        result.add(m);
      }
    }
    // ignore: avoid_print
    print('[TRN-SEARCH] sample=${result.isNotEmpty ? result.first : {}}');
    return result;
  }
}
