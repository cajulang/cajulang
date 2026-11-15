# std/cipher

Authenticated encryption with associated data (AEAD), the record protection of TLS 1.3:

- **AES-GCM** (NIST SP 800-38D) with 16-byte (AES-128) or 32-byte (AES-256) keys; 24-byte keys
  (AES-192) also work.
- **ChaCha20-Poly1305** (RFC 8439) with 32-byte keys.

Both take a 12-byte nonce and add a 16-byte tag. Everything is a binary string (`str`).

```caju
import "std/cipher"
import "std/crypto"

key, _ := crypto.random_bytes(32)
nonce, _ := crypto.random_bytes(12)        # never reuse a nonce with the same key
sealed, err := cipher.chacha20_poly1305_seal(key, nonce, "secret", "header")
plain, err := cipher.chacha20_poly1305_open(key, nonce, sealed, "header")
if err != nil { print(err.Error()) }       # "cipher: message authentication failed"
```

`seal` gives `ciphertext || tag`. `open` recomputes the tag, compares it in constant time
(`crypto.constant_time_eq`) and only then decrypts: a changed ciphertext, tag, aad, nonce or key
gives the error `cipher: message authentication failed` and no plaintext.

## One-shot functions

| function | |
|---|---|
| `aes_gcm_seal(key, nonce, plaintext, aad) -> (str, error)` | AES-GCM |
| `aes_gcm_open(key, nonce, sealed, aad) -> (str, error)` | |
| `chacha20_poly1305_seal(key, nonce, plaintext, aad) -> (str, error)` | ChaCha20-Poly1305 |
| `chacha20_poly1305_open(key, nonce, sealed, aad) -> (str, error)` | |

## Many messages with one key: `Aead`

The one-shot functions set the key up again on every call. For TLS records, make an `Aead` once:
`new_aes_gcm` expands the AES key schedule and builds the GHASH table there.

```caju
a, err := cipher.new_aes_gcm(key)          # or cipher.new_chacha20_poly1305(key)
rec := a.seal(nonce, plaintext, aad)       # panics if the nonce does not have 12 bytes
plain, err := a.open(nonce, rec, aad)
a.overhead()                               # 16
```

`seal`/`open` allocate only their result; the work happens on raw memory.

## Raw primitives

`chacha20(key, nonce, counter, data) -> (str, error)` (RFC 8439 section 2.4, encrypts and
decrypts) and `poly1305(key, msg) -> (str, error)` (a one-time MAC, section 2.5). They have no
authentication or misuse protection of their own: prefer the AEADs.

Constants: `NONCE_SIZE` (12), `TAG_SIZE` (16), `CHACHA20_KEY_SIZE` (32).

## Related: std/crypto

TLS 1.3's key schedule lives in `std/crypto`: `sha384`, `new_sha384`, `hmac_sha384`,
`hkdf_extract(hash, salt, ikm)` and `hkdf_expand(hash, prk, info, length)` (RFC 5869), where
`hash` is `"sha256"` or `"sha384"`.

## Performance and security notes

Measured on 1 MB messages (x86-64, native target): about 55-60 MB/s for AES-128-GCM, 48 MB/s
for AES-256-GCM and 68 MB/s for ChaCha20-Poly1305.

AES uses T-tables (lookup tables indexed by secret data) and GHASH uses 4-bit tables of multiples
of H (Shoup's method). This is **not constant-time against cache-timing attackers on the same
machine** (shared CPU caches); there is no AES-NI path yet. ChaCha20-Poly1305 has no
secret-dependent table lookups or branches: prefer it where that threat matters.

The tests (`lib/cipher_test.caju`) cover the GCM paper / NIST vectors (AES-128 and AES-256,
empty plaintext, aad only, lengths that are not multiples of 16), RFC 8439 (2.8.2 and appendix
A.1-A.5), tampering, and, when `python3` has the `cryptography` module, a cross-check of random
messages against it.
