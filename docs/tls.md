# std/tls: TLS 1.3 clients

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
| `insecure_skip_verify` | accept any certificate: only for tests, anyone in the middle can then read and change everything |

After the handshake, `c.cipher_suite` names the suite and `c.peer_certificates` holds the
server's certificates (leaf first).

## What it does

- TLS 1.3 only (RFC 8446). A server that only speaks TLS 1.2 refuses the handshake, and the error
  says so.
- Key exchange: X25519. Cipher suites: TLS_AES_128_GCM_SHA256, TLS_CHACHA20_POLY1305_SHA256,
  TLS_AES_256_GCM_SHA384 (`std/cipher`).
- The certificate chain is verified with `std/x509` (dates, CA constraints, key usage, path length,
  extended key usage, the host name), and the server's CertificateVerify signature with
  `std/pubkey` (RSA-PSS, ECDSA P-256/P-384, Ed25519).
- Post-handshake: session tickets are ignored (no resumption), KeyUpdate is followed.
- Not supported: session resumption, 0-RTT, client certificates (a server asking for one gets an
  empty Certificate), revocation checks (CRL, OCSP), certificates with name constraints, TLS servers.

## Security notes

- AES runs on tables (no AES-NI): another process on the same machine could learn about keys from
  cache timings. ChaCha20-Poly1305 does not have this problem.
- The record layer checks every record's tag before using it, and any failure ends the connection
  with an alert.
