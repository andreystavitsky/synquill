# synquill_supabase

Supabase adapter for the Synquill offline-first data engine.

## Features

- CRUD sync through the Supabase Dart client.
- `QueryParams` mapping to Supabase/PostgREST filters, sorting, limit, and range.
- Per-request headers applied to Supabase PostgREST builders.
- `watchRemote` support through Supabase Realtime row change events.
- Synquill exception mapping for auth, authorization, validation, conflict,
  not found, gone, server, network, and unknown transport failures.

## Installation

```yaml
dependencies:
  synquill: ^0.9.0
  synquill_supabase: ^0.9.0
  supabase: ^2.13.0
```

Use the pure Dart `supabase` package. Flutter apps can still create their
client through `supabase_flutter` and pass the shared client into adapters.

## Adapter Example

```dart
import 'package:supabase/supabase.dart';
import 'package:synquill_supabase/synquill_supabase.dart';

mixin TodoSupabaseAdapter on SupabaseApiAdapter<Todo> {
  @override
  SupabaseClient get supabaseClient => appSupabaseClient;

  @override
  String get tableName => 'todos';
}
```

Then annotate the model:

```dart
@SynquillRepository(adapters: [TodoSupabaseAdapter])
class Todo extends SynquillDataModel<Todo> {
  // id, fields, fromJson, toJson...
}
```

Run build generation after adding the adapter.

## Realtime

`SupabaseApiAdapter` implements Synquill's `RealtimeApiAdapter`, so repository
watch methods can use `watchRemote: true`.

Supabase Realtime must be enabled for the target table. For reliable delete
events, and for update events that need old row data, configure the table with
`REPLICA IDENTITY FULL` in Postgres.

Supabase Realtime supports a single Postgres change filter per subscription.
Synquill maps `id` subscriptions to an `eq` filter on `idColumn`, or maps one
query filter using `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, or `inList`. Combining
`id` with query filters, passing multiple filters, or using unsupported filter
operators fails with `ApiException` instead of widening the subscription.

## Customization

Override these getters when your Supabase project uses non-default names:

- `schema`, default `public`
- `tableName`, default Synquill plural model type
- `idColumn`, default `id`
- `selectColumns`, default `*`

Override `toSupabaseInsertJson`, `toSupabaseUpdateJson`, or
`toSupabaseReplaceJson` when write payloads differ from model JSON.

Headers passed to adapter methods are merged with `baseHeaders`; per-call
headers win and are forwarded to the Supabase PostgREST builder with
`setHeader`. The `extra` map remains an adapter-level hook for overrides such
as `mergeHeaders` or custom request builders. It is not forwarded to the
Supabase SDK as metadata.

For tests or custom SDK boundaries, override `transport` with a
`SupabaseTransport` implementation. The transport request and response DTOs are
exported from `package:synquill_supabase/synquill_supabase.dart`.
