# Schemas

## `script-module.schema.json`

JSON Schema (draft 2020-12) for script modules (SPEC §9, AD-18), added in Story 12.1.

- `#/$defs/frontMatter`: the YAML front matter of a script file.
- `#/$defs/output`: the JSON a run prints to stdout.

Vigie does not ship a JSON Schema library (AD-16). It decodes both documents with the Swift `Codable` types in
`Packages/Modules/Integrations/Sources/Integrations/Schema`, and CI (`Scripts/check-script-schema.sh` and the
Integrations package tests) checks that the schema and the types accept and reject the same sample documents in
`Packages/Modules/Integrations/Tests/IntegrationsTests/Fixtures/script-schema`. Change the schema, the types and
the fixtures together.

### Versioning

- Both documents may carry `schema: <int>`; it defaults to 1. The schema's `schemaVersion` enum lists the
  versions this Vigie reads; a document with any other version is rejected with an error naming it.
- Bump the version on every breaking change: a new required key, a removed or renamed key, a narrower type or
  enum, and any new front matter key (front matter rejects unknown keys, so an older Vigie must refuse the file
  by its version rather than by an unknown key). Story 12.8 adds `author`, `source` and `version` this way.
- Adding an optional output key is not breaking: output ignores unknown keys.
- Keys are never renamed or repurposed (Conventions). Vigie keeps reading older versions.
- v1 accepts `notify` in the output with any value and ignores it (script-raised alerts are deferred).
