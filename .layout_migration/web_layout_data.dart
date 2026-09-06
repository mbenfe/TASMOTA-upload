/// Expands shape groups into the flat device lists used by the web renderer.
/// Legacy flat lists are accepted so existing published layouts still load.
Map<String, dynamic> normalizeWebLayout(Map<String, dynamic> layout) {
  final applications = layout['applications'];
  if (applications is! List) {
    throw const FormatException('Layout applications must be a list');
  }
  return {
    ...layout,
    'applications': applications.map((application) {
      if (application is! Map) {
        throw const FormatException('Each application must be an object');
      }
      return {
        ...Map<String, dynamic>.from(application),
        'data': expandShapeGroups(application['data']),
      };
    }).toList(),
  };
}

List<Map<String, dynamic>> expandShapeGroups(Object? data) {
  if (data is List) {
    return data.map((device) {
      if (device is! Map) {
        throw const FormatException('Each device must be an object');
      }
      return Map<String, dynamic>.from(device);
    }).toList();
  }
  if (data is! Map) {
    throw const FormatException(
      'Application data must be a list or shape groups',
    );
  }
  final devices = <Map<String, dynamic>>[];
  for (final group in data.entries) {
    if (group.key is! String ||
        (group.key as String).isEmpty ||
        group.value is! List) {
      throw const FormatException(
        'Each shape group must have a name and a device list',
      );
    }
    for (final device in group.value as List) {
      if (device is! Map) {
        throw const FormatException('Each device must be an object');
      }
      if (device.containsKey('shape') && device['shape'] != group.key) {
        throw const FormatException('Device shape conflicts with its group');
      }
      devices.add({...Map<String, dynamic>.from(device), 'shape': group.key});
    }
  }
  return devices;
}
