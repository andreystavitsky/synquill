import 'package:synquill/synquill_core.dart';

/// Test database for queue system integration testing
class TestDatabase extends GeneratedDatabase {
  TestDatabase(super.e);

  @override
  Iterable<TableInfo<Table, DataClass>> get allTables => [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Create sync queue table for testing
      await customStatement('''
        CREATE TABLE sync_queue_items (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          model_type TEXT NOT NULL,
          model_id TEXT NOT NULL,
          payload TEXT NOT NULL,
          op TEXT NOT NULL,
          attempt_count INTEGER NOT NULL DEFAULT 0,
          last_error TEXT,
          next_retry_at INTEGER,
          idempotency_key TEXT,
          status TEXT NOT NULL DEFAULT 'pending',
          created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now')),
          headers TEXT,
          extra TEXT
        )
      ''');
    },
  );
}

/// Test model for queue system integration testing
class TestUser extends SynquillDataModel<TestUser> {
  @override
  final String id;
  final String name;
  final String email;

  TestUser({required this.id, required this.name, required this.email});

  TestUser copyWith({String? id, String? name, String? email}) {
    return TestUser(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
    );
  }

  @override
  TestUser fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'] as String,
      name: json['name'] as String,
      email: json['email'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'email': email};
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TestUser &&
        other.id == id &&
        other.name == name &&
        other.email == email;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ email.hashCode;

  @override
  String toString() => 'TestUser(id: $id, name: $name, email: $email)';
}
