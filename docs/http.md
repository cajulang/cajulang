# std/http

An HTTP/1.1 server and client, over the TCP sockets of `std/net` (Linux x86-64).

## Server

```caju
import "std/http"

http.handle("/", fn(req: *http.Request, res: *http.Response) {
  res.set_header("Content-Type", "text/plain")
  res.write("hello " + req.path)
})
err := http.listen_and_serve("0.0.0.0", 3200)        # or listen_and_serve_workers(host, port, n)
```

A path ending in `/` also handles everything below it. The server runs an event loop (epoll) with
keep-alive and pipelining; handlers run one at a time. For routes with parameters, middlewares
and JSON, use [`github.com/cajulang/web`](https://github.com/cajulang/web).

### Limits and safety

| setting | default | |
|---|---|---|
| `set_idle_timeout(ms)` | 5 s | a kept-alive connection without traffic is closed |
| `set_request_timeout(ms)` | 30 s | a request must arrive whole within this, from its first byte |
| `set_max_body(n)` | 16 MiB | larger bodies get 413 |
| `set_max_connections(n)` | 10000 | more connections are closed as they arrive |
| `set_max_buffered(n)` | 1 GiB | input buffered by every connection together; beyond it, 503 |
| `set_max_requests(n)` | 10000 | requests per connection |
| `set_max_stream_backlog(n)` | 16 MiB | output queued for an upgraded stream (WebSocket) that stopped reading; beyond it, the stream is dropped |

- Requests are parsed strictly: anything a proxy in front could read differently (both
  Content-Length and Transfer-Encoding, conflicting lengths, bare CR or LF, folded or malformed
  headers, control bytes in the target) gets 400 and the connection is closed. Repeated headers
  are joined with `", "` (`Cookie` with `"; "`).
- The body buffer grows as its bytes arrive, never by what Content-Length announces.
- `res.set_header` values with CR, LF or NUL are sent with spaces in their place, and names that
  are not tokens are left out, so a value taken from the request cannot add headers.
- A handler that panics gets a 500 response (and a line on the standard error); the server goes on.
- Paths with `//`, `.` or `..` segments are redirected (301) to the clean path before routing, so
  `/public/../admin` never reaches the handler of `/public/`. The path is not percent-decoded:
  a handler that decodes it (`%2e%2e`) must check the result itself.

## Client

```caju
import "std/http"
import "std/json"

r, err := http.get("http://localhost:3800/api/produtos?q=cocada")
if err != nil { panic(err.Error()) }          # no answer: DNS, connection, timeout, malformed reply
if !r.ok() { print("status " + str(r.status)) }   # 4xx and 5xx are responses, not errors
print(r.header("content-type"))
print(r.body)

payload, _ := json.marshal(order)
r2, err2 := http.post("http://localhost:8080/orders", "application/json", payload)
r3, err3 := http.post_form("http://localhost:8080/login", map[str]str{"email": e, "password": p})

r4, err4 := http.request(&http.ClientRequest{
  method: "PUT",
  url: "http://api.internal:9000/items/7",
  headers: map[str]str{"Authorization": "Bearer " + token, "Content-Type": "application/json"},
  body: "{\"stock\":3}",
  timeout_ms: 5000,
})
```

`ClientRequest`:

| field | |
|---|---|
| `method` | `""` is GET |
| `url` | `http://host[:port]/path?query`; the host is a name or an IPv4 address |
| `headers` | sent as written; `Host`, `User-Agent` and `Content-Length` are added when missing |
| `body` | |
| `timeout_ms` | how long each connect, write and read may wait; 0 is the default (`http.set_client_timeout`, 30 s) |
| `no_redirects` | give 3xx responses back instead of following them (do this when the URL comes from a user: a redirect can point inside your network) |

`ClientResponse`: `status`, `status_text`, `headers` (names in lower case, repeated headers joined
with `", "`), `body`, `url` (the URL that answered, after redirects); `header(name)` in any case,
and `ok()` for a 2xx status.

What it does:

- **Keep-alive**: after a response, the connection waits (up to 8 per host and port) for the next
  request to the same place. One the server closed in the meantime is replaced by a new one.
  `http.close_idle_connections()` closes them.
- **Redirects**: 301, 302, 303, 307 and 308, up to 10. A 303, and a 301 or 302 after a POST, are
  followed with a GET without body (as browsers do); 307 and 308 keep the method and body.
- **Bodies** by `Content-Length`, `Transfer-Encoding: chunked` or until the server closes. A
  `100 Continue` before the response is skipped. Bodies are not decompressed (the client does not
  send `Accept-Encoding`).
- **Names**: `net.resolve` looks in `/etc/hosts`, then asks the DNS servers of `/etc/resolv.conf`
  (A records, cached for their TTL). IPv4 only.

- **https://**: TLS 1.3 or 1.2 through `std/tls` (`docs/tls.md`), with the certificate checked against
  the system's roots and the host name. `ClientRequest.tls` takes a `*tls.Config` (other roots,
  another server name).

Limits: requests run one at a time (Caju has no threads), and the whole body is read into memory.

## Encoding

- `http.query_escape(s)`: every byte but letters, digits and `-_.~` as `%XX`.
- `http.query_unescape(s)`: the reverse; `+` becomes a space.
- `http.encode_form(fields)`: `a=1&b=x%20y`, names in order.
- `http.parse_form(s)`: the reverse, as a `map[str]str`.

## Client safety

- A redirect to another host or port drops `Authorization`, `Cookie`, `Proxy-Authorization` and
  `Host`; a 303 (or a 301/302 after a POST) becomes a GET without body or `Content-Type`.
- URLs, methods and headers with CR, LF, spaces or control bytes are refused with an error.
- A response may have at most `set_max_response_size(n)` bytes (default 64 MiB), 200 header
  lines and 10 informational (1xx) responses before the real one.
