/// Code generator for synquill package.
///
/// This library provides builders for generating database tables, DAOs,
/// repositories, and other synced storage code.
library synquill_gen;

import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:glob/glob.dart';
import 'package:source_gen/source_gen.dart';
import 'package:synquill/synquill.dart';

// Export all builder components
part 'src/adapter_info.dart';
part 'src/aggregate_builder.dart';
part 'src/builder_utils.dart';
part 'src/dao_generator.dart';
part 'src/database_generator.dart';
part 'src/field_validator.dart';
part 'src/file_aggregator.dart';
part 'src/model_analyzer.dart';
part 'src/model_extension_generator.dart';
part 'src/model_info.dart';
part 'src/model_info_registry_generator.dart';
part 'src/repository_generator.dart';
part 'src/table_generator.dart';
part 'src/proxy_builder.dart';
