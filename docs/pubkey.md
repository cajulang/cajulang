# std/pubkey

Public-key signature verification, as TLS 1.3 (CertificateVerify) and X.509 certificate chains
need it: RSA (PKCS #1 v1.5 and PSS), ECDSA on P-256 and P-384, and Ed25519. Verification only:
there is no key generation or signing.

```caju
import "std/pubkey"

err := pubkey.verify_signature("ecdsa-p256-sha256", spki, msg, sig)
if err != nil { print("bad signature: " + err.Error()) }

kind, bits, err := pubkey.key_info(spki)      # "rsa", 2048, nil
```

## API

`verify_signature(alg: str, spki: str, msg: str, sig: str) -> error`

: `nil` when `sig` is a valid signature of `msg` by the key in `spki`, an error otherwise. It
  never panics on bad input. `spki` is a DER SubjectPublicKeyInfo, the form inside a certificate
  (`openssl pkey -pubout -outform DER`). `msg` is the whole message: the function hashes it.

`key_info(spki: str) -> (kind: str, bits: int, err: error)`

: The kind of key, `"rsa"`, `"ecdsa-p256"`, `"ecdsa-p384"` or `"ed25519"`, and its size in bits
  (the modulus size for RSA; 256 or 384 for ECDSA; 256 for Ed25519). It parses and checks the
  key (an EC point must be on the curve) but does not apply the RSA size policy below, so it
  can report the size of a key that `verify_signature` would refuse.

## Algorithms

| `alg` | Key (SPKI algorithm) | Signature |
|---|---|---|
| `rsa-pkcs1-sha256`, `-sha384`, `-sha512` | rsaEncryption | RSASSA-PKCS1-v1_5 |
| `rsa-pkcs1-sha1` | rsaEncryption | the same with SHA-1 (old certificates only) |
| `rsa-pss-sha256`, `-sha384`, `-sha512` | rsaEncryption or id-RSASSA-PSS | RSASSA-PSS, MGF1 with the same hash |
| `ecdsa-p256-sha256`, `ecdsa-p256-sha384` | id-ecPublicKey, prime256v1 | DER `SEQUENCE { r INTEGER, s INTEGER }` |
| `ecdsa-p384-sha384`, `ecdsa-p384-sha256` | id-ecPublicKey, secp384r1 | the same |
| `ed25519` | id-Ed25519 | 64 bytes (RFC 8032), via `crypto.ed25519_verify` |

- **PSS salt length.** The salt length is recovered from the encoding (RFC 8017 EMSA-PSS-VERIFY),
  so any salt length is accepted, as X.509 RSASSA-PSS needs. TLS 1.3 requires the salt to be as
  long as the hash; `verify_signature` accepts that case, but does not enforce it.
- **id-RSASSA-PSS keys** are accepted only for the `rsa-pss-*` algorithms. Their optional
  RSASSA-PSS-params are read but not enforced (the algorithm name decides the hash).
- **ECDSA hashes** longer than the curve are truncated to its leftmost bits (FIPS 186-4).

## Checks and policy

- RSA keys must have 2048 to 16384 bits (`pubkey: RSA key of 1024 bits is too small`), an odd
  modulus and an odd exponent `e > 1` below the modulus. Any such `e` works (65537 is the fast
  common case). The signature must be exactly as long as the modulus and below it.
- PKCS #1 v1.5 compares the whole encoded block with the expected one (DigestInfo with explicit
  NULL parameters), so there is no lax parsing to attack.
- ECDSA public keys must be uncompressed points (`04 || X || Y`) with coordinates below `p` and on
  the curve; compressed points are refused. `r` and `s` must be in `[1, n-1]`.
- The DER reader is strict: definite lengths only, minimal length and integer encodings, no
  negative integers, and no trailing data at any level (after the SPKI, inside the
  AlgorithmIdentifier, after an ECDSA signature).

## Performance

Measured on a laptop (x86-64, WSL2), average of 50 verifications:

| Verify | Time |
|---|---|
| RSA-2048, PKCS #1 v1.5 | 0.5 ms |
| RSA-3072, PSS | 1.2 ms |
| RSA-4096, PKCS #1 v1.5 | 2.1 ms |
| ECDSA P-256 | 1.7 ms |
| ECDSA P-384 | 5.2 ms |
| Ed25519 | 6.2 ms |

Nothing here is constant time: verification only touches public data.

## Inside

- A small arbitrary-precision unsigned integer: 32-bit limbs in `[]int`, so limb products fit in
  64 bits, and Montgomery multiplication (CIOS) for every modular product.
- RSA: `s^e mod n` by square-and-multiply in Montgomery form.
- ECDSA: Jacobian coordinates over GF(p) (Montgomery form, `a = -3` doubling), `u1*G + u2*Q`
  with Shamir's trick, inverses by Fermat's little theorem. The curves are set up on first use.
- SHA-384 is SHA-512 with the SHA-384 initial values, truncated to 48 bytes.
