# std/tls: TLS 1.3 and 1.2 clients

```caju
import "std/tls"

c, err := tls.dial("example.com", 443, nil)
if err != nil { panic(err.Error()) }
c.write("GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n")
while true {
  data, err2 := c.read(65536)
  if err2 != nil || data == "" { break }      # "" with a nil error: the server closed
  print(data)
}
c.close()
```

Most programs use it through `std/http`, which speaks `https://` with it:
`http.get("https://api.github.com/zen")`.

## Config

| field | |
|---|---|
| `server_name` | the name sent in SNI and checked in the certificate (default: the host dialed; an IP address is checked against the certificate's IP addresses) |
| `roots` | the trusted roots (`[]*x509.Certificate`, nil: the system's, see `std/x509`) |
| `alpn` | application protocols offered (`[]str{"http/1.1"}`); `c.protocol` is the one chosen |
| `timeout_ms` | connect, handshake and each read or write (default 30 s) |
| `min_version` | 0x0303 (TLS 1.2, the default) or 0x0304 (TLS 1.3 only) |
| `insecure_skip_verify` | accept any certificate: only for tests, anyone in the middle can then read and change everything |

After the handshake, `c.cipher_suite` names the suite and `c.peer_certificates` holds the
server's certificates (leaf first).

## What it does

- TLS 1.3 (RFC 8446) first; TLS 1.2 (RFC 5246) when the server has nothing newer, unless
  `Config.min_version = 0x0304`. `c.version` is 0x0304 or 0x0303. The downgrade protection of RFC
  8446 is checked: a 1.3 server pushed to 1.2 by something in the middle is refused.
- TLS 1.3: X25519 key exchange; TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256,
  TLS_AES_256_GCM_SHA384 (`std/cipher`).
- TLS 1.2: ECDHE only (X25519, P-256, P-384) with AEAD suites only: ECDHE-ECDSA and ECDHE-RSA with
  AES-128-GCM, AES-256-GCM or ChaCha20-Poly1305; the extended master secret (RFC 7627) when the
  server supports it. Refused: RSA key exchange, finite-field DH, CBC, RC4, 3DES, NULL, TLS 1.0
  and 1.1, renegotiation (a HelloRequest is declined).
- The certificate chain is verified with `std/x509` (dates, CA constraints, key usage, path length,
  extended key usage, the host name), and the server's CertificateVerify signature with
  `std/pubkey` (RSA-PSS, ECDSA P-256/P-384, Ed25519).
- Post-handshake: session tickets are ignored (no resumption), KeyUpdate is followed (1.3).
- The P-256/P-384 key exchange of TLS 1.2 uses `std/pubkey`'s curve arithmetic, which is not
  constant-time; the keys are ephemeral (one handshake), and X25519 (constant-time ladder) is
  preferred whenever the server supports it.
- Not supported: session resumption, 0-RTT, client certificates (a server asking for one gets an
  empty Certificate), revocation checks (CRL, OCSP), certificates with name constraints, TLS servers.

## Security notes

- AES runs on tables (no AES-NI): another process on the same machine could learn about keys from
  cache timings. ChaCha20-Poly1305 does not have this problem.
- The record layer checks every record's tag before using it, and any failure ends the connection
  with an alert.
