// ignore_for_file: deprecated_member_use

import 'package:analyzer/dart/element/type.dart';

/// Information about an adapter that can be applied to models
class AdapterInfo {
  /// The name of the adapter class/mixin.
  final String adapterName;

  /// The import path for the adapter file.
  final String importPath;

  /// The Dart type of the adapter.
  final DartType dartType;

  /// Whether this adapter is generic (has type parameters).
  final bool isGeneric;

  /// Superclass constraints declared by a mixin adapter.
  ///
  /// For example, a mixin declared as `on GraphQLApiAdapter<T>` contributes
  /// `GraphQLApiAdapter`.
  final List<String> superclassConstraints;

  /// Creates a new instance of [AdapterInfo].
  const AdapterInfo({
    required this.adapterName,
    required this.importPath,
    required this.dartType,
    required this.isGeneric,
    this.superclassConstraints = const [],
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdapterInfo &&
        other.adapterName == adapterName &&
        other.importPath == importPath &&
        _listEquals(other.superclassConstraints, superclassConstraints);
  }

  @override
  int get hashCode =>
      adapterName.hashCode ^
      importPath.hashCode ^
      Object.hashAll(superclassConstraints);

  @override
  String toString() {
    return 'AdapterInfo(adapterName: $adapterName, importPath: $importPath, '
        'isGeneric: $isGeneric, '
        'superclassConstraints: $superclassConstraints)';
  }
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) return false;
  }
  return true;
}
