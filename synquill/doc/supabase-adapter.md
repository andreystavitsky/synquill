# Supabase API Adapter

The `synquill_supabase` package lets Synquill repositories use Supabase as the
remote API data source. It is a sibling transport package to
`synquill_graphql`.

## Setup

Add the packages:

```yaml
dependencies:
  synquill: ^0.9.0
  synquill_supabase: ^0.9.0
  supabase: ^2.13.0
```

Define a model adapter mixin:

```dart
mixin TodoSupabaseAdapter on SupabaseApiAdapter<Todo> {
  @override
  SupabaseClient get supabaseClient => appSupabaseClient;

  @override
  String get tableName => 'todos';
}
```

Attach it to the model:

```dart
@SynquillRepository(adapters: [TodoSupabaseAdapter])
class Todo extends SynquillDataModel<Todo> {
  // id, fields, fromJson, toJson...
}
```

Run build generation after adding the adapter.

## Query Mapping

`QueryParams` filters map to Supabase/PostgREST operators:

- equality and inequality: `eq`, `neq`
- comparisons: `gt`, `gte`, `lt`, `lte`
- strings: `ilike` with contains, starts-with, and ends-with patterns
- lists: `in`, `not.in`
- null checks: `is`, `not.is`

Sorting maps to ordered Supabase `order` calls. Limit-only pagination maps to
`limit`. Offset pagination maps to an inclusive Supabase `range`, so an offset
requires a limit.

`findOne(id, queryParams: ...)` applies both the id lookup and supported query
filters, which is useful for tenant or soft-delete constraints.

## Realtime

`SupabaseApiAdapter` implements Synquill's realtime adapter contract. Repository
watch methods can use `watchRemote: true` when Supabase Realtime is enabled for
the table.

For reliable delete events, and for update events that need old row data,
configure the table with `REPLICA IDENTITY FULL`.

Supabase Realtime supports one Postgres change filter per subscription.
Synquill maps an `id` subscription to an `eq` filter on `idColumn`, or maps one
query filter using `eq`, `neq`, `gt`, `gte`, `lt`, `lte`, or `inList`. Combining
`id` with query filters, passing multiple filters, or using unsupported filter
operators throws `ApiException` instead of subscribing too broadly.

## Headers And Extra

Headers passed to adapter methods are merged with `baseHeaders`; per-call
headers win and are applied to Supabase PostgREST builders through `setHeader`.

The `extra` map is kept as an adapter-level hook for overrides such as
`mergeHeaders` or custom request-building logic. Synquill does not forward
`extra` to the Supabase SDK as metadata because the SDK does not expose a
matching request metadata channel.

## Customization

Override:

- `schema`, default `public`
- `tableName`, default Synquill plural model type
- `idColumn`, default `id`
- `selectColumns`, default `*`
- `toSupabaseInsertJson`, `toSupabaseUpdateJson`, `toSupabaseReplaceJson`
  when write payloads differ from model JSON
- `transport` when tests or applications need a custom `SupabaseTransport`
  boundary; transport DTOs are exported by
  `package:synquill_supabase/synquill_supabase.dart`
