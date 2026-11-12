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

- Both documents may carry `schema: <int>`. A document without it is **version 1**; new files write the current
  version, **2**. The schema's `schemaVersion` enum lists the versions this Vigie reads (`[1, 2]`); a document with
  any other version is rejected with an error naming it. Older versions stay readable forever.
- Bump the version on every breaking change: a new required key, a removed or renamed key, a narrower type or
  enum, and any new front matter key (front matter rejects unknown keys, so an older Vigie must refuse the file
  by its version rather than by an unknown key).
- A key added by a version is rejected in files that declare an older one (the schema's `if`/`else` on
  `frontMatter`; Swift: `ScriptSchemaError.Reason.requiresSchema`). A file using it must say so with `schema:`.
- Adding an optional output key is not breaking: output ignores unknown keys.
- Keys are never renamed or repurposed (Conventions). Vigie keeps reading older versions.
- v1 accepts `notify` in the output with any value and ignores it (script-raised alerts are deferred).

| Version | Adds | Story |
|---|---|---|
| 1 | Front matter `id`, `name`, `icon`, `interval`, `runtime`, `widget`, `surfaces`, `priority`, `settings`; the output document | 12.1 |
| 2 | Optional front matter provenance: `author` (non-empty string), `source` (`https://` URL with a host, no spaces), `version` (`1`, `1.2`, `1.2.3`, with optional `-prerelease` and `+build`). Output unchanged. | 12.8 (schema part, built with 12.9) |

`source` is what the file claims. Link installs (Story 12.9) record the URL they actually downloaded from in
`local.toml` and show a file whose `source` host differs from that URL's host as coming "from another site".
