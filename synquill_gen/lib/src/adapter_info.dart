// ignore_for_file: deprecated_member_use

part of synquill_gen;

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

  /// Creates a new instance of [AdapterInfo].
  const AdapterInfo({
    required this.adapterName,
    required this.importPath,
    required this.dartType,
    required this.isGeneric,
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AdapterInfo &&
        other.adapterName == adapterName &&
        other.importPath == importPath;
  }

  @override
  int get hashCode => adapterName.hashCode ^ importPath.hashCode;

  @override
  String toString() {
    return 'AdapterInfo(adapterName: $adapterName, importPath: $importPath, '
        'isGeneric: $isGeneric)';
  }
}
