# Notes recovery key format

Story 15.1, AD-9. The recovery key is the notes key (32 bytes) written so a person can copy it, store it and type
it back. Code: `Packages/Modules/Notes/Sources/Notes/RecoveryKey.swift`.

## Bytes

| Offset | Length | Content |
| --- | --- | --- |
| 0 | 1 | Format version, `0x01` |
| 1 | 32 | The notes key |
| 33 | 2 | Checksum: the first 2 bytes of SHA-256 over bytes 0–32 (version + key) |

35 bytes = 280 bits.

## Text

- Crockford base32, alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (no `I`, `L`, `O`, `U`), 5 bits per character,
  most significant bit first, no padding: exactly **56 characters**.
- Uppercase, written as **8 groups of 7** joined by `-`:
  `0XXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX-XXXXXXX`.
  With version 1 the first character is always `0`.

## Parsing

- Case-insensitive; spaces, line breaks and dashes are ignored wherever they are.
- Crockford substitutions: `O` reads as `0`, `I` and `L` as `1`. Any other character outside the alphabet is
  refused.
- Not 56 characters → refused (length). Checksum mismatch → refused as a typo (a single wrong character is
  always caught; a random error passes with probability 1/65536). Unknown version → refused.

## Key id

`key_id` = the first 8 bytes of SHA-256 of the 32-byte key, as 16 lowercase hex characters. It appears in every
note file's plaintext header (`{"format":1,"key_id":"…"}`) and in the folder's `notes-key.json` marker. Test vector:
the all-zero key has `key_id` `66687aadf862bd77`.

## Why a version byte and a 2-byte checksum

`1 + 32 + 2 = 35` bytes fill 8 × 7 base32 characters exactly; a version byte lets the format change later, and a
2-byte checksum catches far more typos than 1 byte for no extra characters.
