# std/websocket

WebSocket (RFC 6455) clients and servers, over `std/net` and `std/http` (Linux x86-64). Plain
`ws://` only: `wss://` needs TLS, which Caju does not have yet.

## Client

Blocking, in the style of the rest of the library: `read` waits for the next message.

```caju
import "std/websocket"

ws, err := websocket.dial("ws://localhost:3800/live")
if err != nil { panic(err.Error()) }
ws.send_text("hello")
ws.send_json(map[str]any{"type": "subscribe", "room": 7})
while true {
  m, err := ws.read()
  if err != nil { break }                 # *websocket.CloseError: err.code, err.reason
  if m.is_text() { print(m.text()) }
}
ws.close(websocket.NORMAL, "bye")
```

`dial_with(url, &websocket.Options{...})`:

| option | |
|---|---|
| `headers` | extra headers of the handshake (`Authorization`...) |
| `protocols` | the subprotocols offered; `ws.protocol` is the one the server chose |
| `timeout_ms` | connect, handshake and each write (default 30 s) |
| `ping_interval_ms` | when nothing arrived for this long, send a ping; no answer by the next interval ends the connection |
| `reconnect` | when the connection drops (or the server closes with a code other than 1000 or 1008), `read` and `send` dial again |
| `reconnect_max_ms` | the backoff starts at 250 ms and doubles up to this (default 30 s) |
| `max_retries` | attempts in a row before giving up (0: no limit) |
| `max_message` | the largest message accepted (default 16 MB) |

- `ws.on_open(fn(c))` runs after each reconnection: subscribe again there. `ws.reconnects`
  counts them.
- `ws.set_read_timeout(ms)`: `read` gives up after that long with an error ending in
  "timed out"; the connection stays usable.
- Pings from the server are answered inside `read`, and fragmented messages are joined there.
- For several connections in one process: watch `ws.fd()` with `net.Poller`, and call `read`
  while `ws.buffered()` before waiting again.

## Server

Inside `std/http`'s event loop, so also inside `github.com/cajulang/web`. The handler accepts
the handshake and registers callbacks; the loop delivers the messages.

```caju
import "std/http"
import "std/websocket"

let room = map[int]*websocket.Conn{}

http.handle("/live", fn(req: *http.Request, res: *http.Response) {
  ws, err := websocket.accept(req, res)        # 101, or 400/426 written to res and err set
  if err != nil { return }
  room[ws.id] = ws
  ws.send_text("welcome")
  ws.on_message(fn(c: *websocket.Conn, m: *websocket.Message) {
    for _, o := range room { o.send_text(m.text()) }    # a broadcast
  })
  ws.on_close(fn(c: *websocket.Conn, code: int, reason: str) { delete(room, c.id) })
})
http.every(30000, fn() { for _, o := range room { o.send_text("tick") } })
http.listen_and_serve("0.0.0.0", 3800)
```

`accept_with(req, res, &websocket.Options{protocols: ..., ping_interval_ms: ..., max_message: ...})`:
`protocols` are the ones the server accepts, in order of preference. With `ping_interval_ms`,
the server pings quiet clients and closes the ones that do not answer. `on_close` runs once,
with code 1006 (`ABNORMAL`) when the connection just dropped.

Callbacks run one at a time in the event loop, like HTTP handlers: a slow callback delays every
connection. With `listen_and_serve_workers`, each process has its own connections (a broadcast
reaches only the ones in the same process).

## How std/http hands the connection over

`res.upgrade(h)` (after setting status 101) turns the connection into an `http.Stream` once the
response is sent: the loop calls `h.stream_open(s)`, then `h.stream_data(s, bytes)` for what
arrives and `h.stream_closed(s)` once at the end; `s.write(data)` queues output and `s.close()`
ends it after the output. Streams are never closed for being idle. `http.every(ms, f)` runs `f`
between events. Another protocol over HTTP/1.1 Upgrade can use the same interface
(`http.StreamHandler`).
