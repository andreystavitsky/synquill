// ignore_for_file: strict_top_level_inference

import 'package:build/build.dart';


/// Creates a no-op builder that does nothing during the build process.
///
/// This is used as a placeholder builder implementation.
Builder proxyBuilder(_) => _Noop();

class _Noop implements Builder {
  @override
  final buildExtensions = const <String, List<String>>{};
  @override
  Future<void> build(BuildStep _) async {}
}
