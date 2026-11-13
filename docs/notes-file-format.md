# Note file format

Story 15.2, AD-10. One file per note in the notes folder (`[modules.notes] folder`, default `~/Notes/Vigie`).
Code: `Packages/Modules/Notes/Sources/Notes/Storage/NoteFile.swift`.

## File name

`<id>.vnote`, where `<id>` is the note's UUID in lowercase (`3f2a…-….vnote`). The name never changes when the title
changes: the title lives inside the ciphertext, so the folder listing shows nothing about the note's content.

Other names in the folder:

| Name | Meaning |
| --- | --- |
| `notes-key.json` | Key marker (Story 15.1): the header line below, alone. |
| `.<id>.vnote.icloud` | iCloud placeholder of a note not downloaded yet. |
| `.<id>.vnote.<uuid>.tmp` | Transient: a write in progress (renamed over `<id>.vnote`). |

## Bytes (format 1)

| Offset | Length | Content |
| --- | --- | --- |
| 0 | h | Header line, UTF-8 JSON with sorted keys: `{"format":1,"key_id":"<16 hex>"}` |
| h | 1 | Line feed `0x0A` |
| h + 1 | 12 | ChaCha20-Poly1305 nonce (random for every write) |
| h + 13 | n | Ciphertext of the payload (n = payload length) |
| h + 13 + n | 16 | Poly1305 tag |

Bytes `h + 1` to the end are CryptoKit's `ChaChaPoly.SealedBox.combined`. With a 16-character `key_id` the header
line is 40 bytes (h = 40), so the ciphertext starts at byte 41.

- **Key:** the notes key (32 bytes, `SyncedKey`). `key_id` = hex of the first 8 bytes of SHA-256 of the key.
- **Additional authenticated data:** the header line bytes, line feed included (bytes `0` to `h`). Changing the
  header in any way, even re-ordering its keys, makes the file fail to open.
- **Why ChaCha20-Poly1305:** CryptoKit authenticated encryption with a 96-bit random nonce, constant-time in
  software; AES-GCM would do as well. A future format changes `format`.

## Payload

UTF-8 JSON, sorted keys:

```json
{"body":"# Groceries\nmilk","created":"2026-11-13T09:41:00.000Z","format":1,"id":"3F2A…","modified":"2026-11-13T09:42:10.512Z","title":"Groceries"}
```

| Key | Type | Content |
| --- | --- | --- |
| `id` | UUID string | Same as the file name (the payload wins if they differ). |
| `title` | string | First non-empty line of the body, trimmed, leading `#` removed, at most 120 characters; `<title> (conflict)` for a conflict copy until it is edited. |
| `body` | string | The note, Markdown. |
| `created`, `modified` | ISO 8601 UTC, milliseconds | Dates. |
| `format` | int | `1`. |

## Reading

1. Read the header line (at most 512 bytes before the line feed). No valid header → unreadable.
2. `format` other than 1 → unreadable (a newer Vigie), never rewritten.
3. `key_id` not the held key's → **locked**: never decrypted, and the module writes nothing to the folder
   (AD-10) until the key matches.
4. Open the sealed box with the header line as additional data. Failure → unreadable (tampered, truncated,
   header changed); the file is left as is.

Plaintext exists only in memory. Logs carry file names, ids and counts, never titles or bodies.
