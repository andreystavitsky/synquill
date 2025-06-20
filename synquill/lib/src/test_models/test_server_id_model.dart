import 'index.dart';

/// Test model using server-generated IDs
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server,
  adapters: [],
)
class ServerTestModel extends SynquillDataModel<ServerTestModel> {
  @override
  final String id;

  final String name;
  final String description;

  ServerTestModel({
    required this.id,
    required this.name,
    required this.description,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
      };

  @override
  ServerTestModel fromJson(Map<String, dynamic> json) => ServerTestModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );

  factory ServerTestModel.fromJson(Map<String, dynamic> json) =>
      ServerTestModel(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String,
      );

  ServerTestModel.fromDb({
    required this.id,
    required this.name,
    required this.description,
  });

  @override
  ServerTestModel fromDb() => this;
}

/// Test model using client-generated IDs (for comparison)
@SynquillRepository(
  adapters: [],
)
class ClientTestModel extends SynquillDataModel<ClientTestModel> {
  @override
  final String id;

  final String name;

  ClientTestModel({
    String? id,
    required this.name,
  }) : id = id ?? generateCuid();

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
      };

  @override
  ClientTestModel fromJson(Map<String, dynamic> json) => ClientTestModel(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  factory ClientTestModel.fromJson(Map<String, dynamic> json) =>
      ClientTestModel(
        id: json['id'] as String,
        name: json['name'] as String,
      );

  ClientTestModel.fromDb({
    required this.id,
    required this.name,
  });

  @override
  ClientTestModel fromDb() => this;
}

/// Server ID model with One-to-Many relationships
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server,
  adapters: [],
  relations: [
    OneToMany(
      target: ServerChildModel,
      mappedBy: 'parentId',
      cascadeDelete: true,
    ),
  ],
)
class ServerParentModel extends SynquillDataModel<ServerParentModel> {
  @override
  final String id;

  final String name;
  final String category;

  ServerParentModel({
    required this.id,
    required this.name,
    required this.category,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
      };

  @override
  ServerParentModel fromJson(Map<String, dynamic> json) => ServerParentModel(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
      );

  factory ServerParentModel.fromJson(Map<String, dynamic> json) =>
      ServerParentModel(
        id: json['id'] as String,
        name: json['name'] as String,
        category: json['category'] as String,
      );

  ServerParentModel.fromDb({
    required this.id,
    required this.name,
    required this.category,
  });

  @override
  ServerParentModel fromDb() => this;
}

/// Server ID model with Many-to-One relationship
@SynquillRepository(
  idGeneration: IdGenerationStrategy.server,
  adapters: [],
  relations: [
    ManyToOne(target: ServerParentModel, foreignKeyColumn: 'parentId'),
  ],
)
class ServerChildModel extends SynquillDataModel<ServerChildModel> {
  @override
  final String id;

  final String name;
  final String parentId;
  final String data;

  ServerChildModel({
    required this.id,
    required this.name,
    required this.parentId,
    required this.data,
  });

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'data': data,
      };

  @override
  ServerChildModel fromJson(Map<String, dynamic> json) => ServerChildModel(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String,
        data: json['data'] as String,
      );

  factory ServerChildModel.fromJson(Map<String, dynamic> json) =>
      ServerChildModel(
        id: json['id'] as String,
        name: json['name'] as String,
        parentId: json['parentId'] as String,
        data: json['data'] as String,
      );

  ServerChildModel.fromDb({
    required this.id,
    required this.name,
    required this.parentId,
    required this.data,
  });

  @override
  ServerChildModel fromDb() => this;
}
