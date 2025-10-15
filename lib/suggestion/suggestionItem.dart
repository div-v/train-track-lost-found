import 'railradar_client.dart';

class SuggestionItem {
  final String type; // 'station' or 'train'
  final String codeOrNumber;
  final String name;
  const SuggestionItem({
    required this.type,
    required this.codeOrNumber,
    required this.name,
  });
}

class RailRadarRepository {
  final RailRadarClient client;
  List<SuggestionItem> _cache = [];

  RailRadarRepository(this.client);

  // Preload stations and trains for fast local filtering
  Future<void> warmAll() async {
    final stPairs = await client.fetchAllStationsKvs(); // [["NDLS","NDLS - New Delhi"], ...]
    final trPairs = await client.fetchAllTrainsKvs();   // [["12951","12951 - Rajdhani Express"], ...]
    final stations = stPairs.map((pair) {
      final code = pair.isNotEmpty ? pair[0].toString() : '';
      final label = pair.length > 1 ? pair[1].toString() : code;
      final name = label.contains(' - ') ? label.split(' - ').last : label;
      return SuggestionItem(type: 'station', codeOrNumber: code, name: name);
    }).toList();
    final trains = trPairs.map((pair) {
      final no = pair.isNotEmpty ? pair[0].toString() : '';
      final label = pair.length > 1 ? pair[1].toString() : no;
      final name = label.contains(' - ') ? label.split(' - ').last : label;
      return SuggestionItem(type: 'train', codeOrNumber: no, name: name);
    }).toList();
    _cache = [...stations, ...trains];
    // ignore: avoid_print
    print('[WARM] stations=${stations.length} trains=${trains.length} total=${_cache.length}');
  }

  List<SuggestionItem> filter(String q) {
    final s = q.toLowerCase().trim();
    if (s.isEmpty) return const [];
    return _cache.where((it) =>
      it.codeOrNumber.toLowerCase().contains(s) || it.name.toLowerCase().contains(s)).take(50).toList();
  }

  // Optional remote search (can be re-enabled later)
  Future<List<SuggestionItem>> searchTrainsRemote(String q) async {
    final list = await client.searchTrains(q, limit: 25);
    return list.map((m) => SuggestionItem(
      type: 'train',
      codeOrNumber: (m['trainNumber'] ?? m['number'] ?? '').toString(),
      name: (m['trainName'] ?? m['name'] ?? '').toString(),
    )).toList();
  }

  bool get ready => _cache.isNotEmpty;
}
