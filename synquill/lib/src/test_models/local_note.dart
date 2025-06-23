// ignore_for_file: public_member_api_docs

import 'package:synquill/src/test_models/index.dart';

/// A simple local-only note model for testing localOnly functionality
@SynquillRepository(
  localOnly: true,
  relations: [ManyToOne(target: User, foreignKeyColumn: 'ownerId')],
)
class LocalNote extends SynquillDataModel<LocalNote> {
  @override
  final String id;

  final String ownerId;

  /// The content of the note
  String content;

  /// Optional category for the note
  String? category;

  LocalNote({
    /// Unique identifier for the note (CUID)
    String? id,

    /// The content of the note
    required this.content,
    required this.ownerId,

    /// Optional category for the note
    this.category,
  }) : id = id ?? generateCuid();

  LocalNote.fromDb({
    required this.id,
    required this.content,
    required this.ownerId,
    this.category,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastSyncedAt,
  }) {
    this.createdAt = createdAt;
    this.updatedAt = updatedAt;
    this.lastSyncedAt = lastSyncedAt;
  }
}
