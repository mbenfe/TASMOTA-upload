import 'package:adoweb/global_classes.dart';
import 'package:adoweb/my_models/adomob_app_cfg.dart';
import 'package:adoweb/utils/web_layout_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final device = <String, dynamic>{
    'id': 11,
    'location': 'Emballage',
    'genre': 'CF+',
    'master': 'LaboEmballage_11',
    'details': 'details_LaboEmballage_11',
    'label': 'Emballage',
    'column': 1370,
    'row': 15,
    'unit_w': 195.0,
    'scale_h': 350.0,
    'color': 0,
    'etage': 2,
    'rotate': 0,
    'slave': <String>['sensor'],
  };
  Map<String, dynamic> layout(Object data) => {
    'applications': [
      {
        'type': 'iPlan',
        'label': 'Plan',
        'level': 1,
        'virtuel': 0,
        'data': data,
      },
    ],
  };

  test('Grouped and legacy layouts produce identical models and bundles', () {
    final grouped = layout({
      'Froid': [device],
    });
    final legacy = layout([
      {...device, 'shape': 'Froid'},
    ]);
    final normalized = normalizeWebLayout(grouped);
    expect(normalized, normalizeWebLayout(legacy));
    final application = normalized['applications'][0] as Map<String, dynamic>;
    final model = ListElementApp.fromJson(application);
    final bundle = Bundle.fromJson(application['data'][0]);
    expect(model.data.single.shape, 'Froid');
    expect(model.data.single.slave, ['sensor']);
    expect(bundle.shape, 'Froid');
    expect(bundle.genre, 'CF+');
    expect(bundle.master, 'LaboEmballage_11');
    expect(bundle.column, 1370);
    expect(bundle.row, 15);
    expect(bundle.unitW, 195);
    expect(bundle.scaleH, 350);
    expect(device.containsKey('shape'), isFalse);
    expect(grouped['applications'][0]['data'], isA<Map>());
  });

  test(
    'Multiple shapes, duplicate IDs across shapes and optional fields survive',
    () {
      final rows = expandShapeGroups({
        'Froid': [device],
        'sonde': [
          {...device, 'master': 'sensor'},
        ],
        'PieChart': [
          {
            'label': ['Main'],
            'slave': ['main'],
          },
        ],
      });
      expect(rows.map((row) => row['shape']), ['Froid', 'sonde', 'PieChart']);
      expect(rows[0]['id'], rows[1]['id']);
      expect(rows[0]['details'], device['details']);
      expect(rows[2]['label'], ['Main']);
      expect(expandShapeGroups({}), isEmpty);
      expect(expandShapeGroups([]), isEmpty);
    },
  );

  test('Malformed groups fail explicitly', () {
    for (final invalid in [
      null,
      5,
      {'Froid': {}},
      {
        'Froid': [5],
      },
      {
        'Froid': [
          {'shape': 'sonde'},
        ],
      },
      {'': []},
    ]) {
      expect(() => expandShapeGroups(invalid), throwsFormatException);
    }
  });
}
