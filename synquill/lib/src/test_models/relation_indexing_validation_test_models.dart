// ignore_for_file: public_member_api_docs

import 'package:synquill/synquill.dart';

/// Test model with a ManyToOne relation that should be automatically indexed
@SynquillRepository(
  relations: [
    ManyToOne(target: IndexingTestCategory, foreignKeyColumn: 'categoryId'),
  ],
)
class IndexingTestProduct extends SynquillDataModel<IndexingTestProduct> {
  @override
  final String id;
  final String name;

  /// This field should be automatically indexed since it's a foreign key
  /// for ManyToOne relation defined at repository level
  final String categoryId;

  IndexingTestProduct({
    required this.id,
    required this.name,
    required this.categoryId,
  });

  /// Required constructor for Drift integration
  IndexingTestProduct.fromDb({
    required this.id,
    required this.name,
    required this.categoryId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
    SyncStatus? syncStatus,
  }) {
    this.syncStatus = syncStatus ?? SyncStatus.synced;
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  @override
  factory IndexingTestProduct.fromJson(Map<String, dynamic> json) {
    return IndexingTestProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'categoryId': categoryId,
    };
  }
}

/// Test model with OneToMany relation
@SynquillRepository(
  relations: [
    OneToMany(target: IndexingTestProduct, mappedBy: 'categoryId'),
  ],
)
class IndexingTestCategory extends SynquillDataModel<IndexingTestCategory> {
  @override
  final String id;
  final String name;

  IndexingTestCategory({
    required this.id,
    required this.name,
  });

  /// Required constructor for Drift integration
  IndexingTestCategory.fromDb({
    required this.id,
    required this.name,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  @override
  factory IndexingTestCategory.fromJson(Map<String, dynamic> json) {
    return IndexingTestCategory(
      id: json['id'] as String,
      name: json['name'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
    };
  }
}

/// Test model that SHOULD cause a build error if someone adds @Indexed
/// annotation to a foreign key field
@SynquillRepository(
  relations: [
    ManyToOne(target: IndexingTestCategory, foreignKeyColumn: 'categoryId'),
  ],
)
class InvalidProduct extends SynquillDataModel<InvalidProduct> {
  @override
  final String id;
  final String name;

  /// This SHOULD cause a build error: foreign key fields cannot have @Indexed
  /// annotation because they are automatically indexed
  ///
  /// Uncomment the next line to test the validation:
  // @Indexed()
  final String categoryId;

  InvalidProduct({
    required this.id,
    required this.name,
    required this.categoryId,
  });

  /// Required constructor for Drift integration
  InvalidProduct.fromDb({
    required this.id,
    required this.name,
    required this.categoryId,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  @override
  factory InvalidProduct.fromJson(Map<String, dynamic> json) {
    return InvalidProduct(
      id: json['id'] as String,
      name: json['name'] as String,
      categoryId: json['categoryId'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'categoryId': categoryId,
    };
  }
}

/// Test model that demonstrates proper use of @Indexed on non-relation fields
@SynquillRepository()
class TestUser extends SynquillDataModel<TestUser> {
  @override
  final String id;

  /// This is fine - @Indexed on a non-relation field
  @Indexed(unique: true)
  final String email;

  /// This is also fine - regular field with index
  @Indexed()
  final String username;

  TestUser({
    required this.id,
    required this.email,
    required this.username,
  });

  /// Required constructor for Drift integration
  TestUser.fromDb({
    required this.id,
    required this.email,
    required this.username,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }

  @override
  factory TestUser.fromJson(Map<String, dynamic> json) {
    return TestUser(
      id: json['id'] as String,
      email: json['email'] as String,
      username: json['username'] as String,
    );
  }

  @override
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'username': username,
    };
  }
}
