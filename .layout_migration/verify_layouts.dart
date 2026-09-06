import 'dart:convert';
import 'dart:io';
import 'web_layout_data.dart';

Object? canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}

void main() {
  final originals = jsonDecode(File('.layout_migration/original_layouts.json').readAsStringSync()) as Map;
  var count = 0;
  for (final entry in originals.entries) {
    var text = File('config/${entry.key}').readAsStringSync();
    if (text.startsWith('\ufeff')) text = text.substring(1);
    final grouped = jsonDecode(text) as Map<String, dynamic>;
    final flat = normalizeWebLayout(grouped);
    final legacy = normalizeWebLayout(Map<String, dynamic>.from(entry.value));
    final applications = flat['applications'] as List;
    for (var i = 0; i < applications.length; i++) {
      final actual = (applications[i]['data'] as List).map((x) => jsonEncode(canonical(x))).toList()..sort();
      final expected = (legacy['applications'][i]['data'] as List).map((x) => jsonEncode(canonical(x))).toList()..sort();
      if (jsonEncode(actual) != jsonEncode(expected)) throw StateError('Lost fields in ${entry.key} application $i');
      count += actual.length;
    }
  }
  for (final invalid in [null, 5, {'Froid': {}}, {'Froid': [5]}, {'Froid': [{'shape': 'sonde'}]}]) {
    var rejected = false;
    try { expandShapeGroups(invalid); } on FormatException { rejected = true; }
    if (!rejected) throw StateError('Malformed input accepted');
  }
  if (expandShapeGroups({}).isNotEmpty || expandShapeGroups([]).isNotEmpty) throw StateError('Empty layout failed');
  print('PASS: ${originals.length} layouts, $count entries, all fields preserved, legacy compatibility and malformed-input checks.');
}
