# Changelog

All notable changes to Caju. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the project uses [Semantic Versioning](https://semver.org/). Each release on GitHub takes its
notes from the section of its version here (`tools/changelog.sh`).

## [Unreleased]

### Added
- `docs/platform-matrix.md`: what every built-in, standard-library module and `caju` command does on
  linux, windows, wasm in Node and wasm in a browser (works, emulated, refused at compile time,
  error at run time).
- Windows: `alloc`, `free`, `peek8/16/32/64`, `poke8/16/32`, `readstr` and `readwstr` (raw memory
  for DLL calls) now work.
- Windows: `os.nanotime`, `os.unix_time`, `os.sleep`, `os.stdout`, `os.stderr`, `os.eprintln`,
  `os.read_line`, `os.read_stdin`, `os.is_terminal` and `crypto.random_bytes` now build and work
  (QueryPerformanceCounter, GetSystemTimeAsFileTime, WriteFile/ReadFile, GetConsoleMode,
  BCryptGenRandom). The standard library reaches the system through intrinsics each runtime
  implements (`__nanotime`, `__unix_nano`, `__random`, `__write`, `__read`, `__isatty`).
- `os.unix_nano()`: the wall clock in nanoseconds.
- The WebAssembly host answers `os.is_terminal` (option `isatty`; `tools/wasm/run.mjs` uses Node's
  `tty.isatty`).

### Changed
- **Breaking:** a program that can reach an `extern` (DLL) call or a raw-memory built-in (`alloc`,
  `free`, `peek*`, `poke*`, `readstr`, `readwstr`) is refused with a Platform error when compiling
  for `linux` or `wasm` (before, raw memory was "not supported yet" everywhere, and an `extern`
  call was refused even in code nothing called; now unreachable code builds).
- `caju pkg` resolves versions before downloading: visiting a version reads only its `caju.toml`
  (from the cache, or from git without the rest of the files) and only the versions it chooses are
  downloaded. Installing a project whose dependencies ask for ui 0.3.0 and ui 0.4.1 no longer
  downloads ui 0.3.0. A release with a wrong caju.toml, a missing repository or a conflict of
  major versions is now reported before anything is downloaded.

### Fixed
- Windows: `os.args`, `os.environ`, `os.getenv` and `os.lookup_env` crashed at run time (the
  arguments pointer was never set); the runtime now builds them from the command line and the
  environment block, in UTF-8.
- The platform pass skipped programs made of a single file: their `# caju:platforms` lines above
  functions were ignored.
- `CAJU_SKIP_SLEEP=0` skipped `os.sleep` as `=1` does (the browser host sets `=0`, so sleep never
  waited in a browser); only `CAJU_SKIP_SLEEP=1` skips now.
- `crypto.random_bytes` above 64 KB failed in WebAssembly (the limit of `getRandomValues`).
- `os.read_stdin` after `os.read_line` lost what `read_line` had read past its line.

## [0.9.1] - 2026-11-15

### Fixed
- In an imported module, calling a function held in a `for ... := range` variable
  (`for _, f := range fns { f() }`) or in a type-switch binding failed with "The function ... does
  not exist": the linker renamed the variable but not the call (the same kind of bug 0.9.0 fixed
  for closure parameters).

## [0.9.0] - 2026-11-15

### Changed
- **Breaking:** `sleep` is no longer part of the language. Waiting is the operating system's
  business, so it lives in the standard library: `import "std/os"` and call `os.sleep(seconds)`
  (fractions too). A program that calls `sleep(...)` gets a compile error that says so, and
  `sleep` is now an ordinary name a program may use for its own function. Inside the standard
  library, `os.sleep` uses the intrinsic `__sleep`, which each runtime implements (Linux, Windows,
  WebAssembly).

### Fixed
- In an imported module, a closure that called one of its own function-valued parameters or
  locals (`return fn(done: fn()) { done() }`) failed with "The function "done" does not exist":
  the linker renamed the parameter but not the call.

## [0.8.0] - 2026-11-15

### Added
- Platforms: a program that can reach code its target cannot run is refused at compile time with a
  "Platform error" and the chain of calls (instead of building and failing when it runs). Code
  declares its targets with `# caju:platforms linux wasm` in a file's header or above a function,
  and packages with `platforms = [...]` in caju.toml; on Windows, functions that make Linux system
  calls are refused. Only reachable code counts (calls, function values, interface calls to the
  types that are constructed). `std/net` declares `linux`. `caju test --target X` skips the test
  files that need another platform. `docs/platforms.md`.
- `std/tls`: TLS 1.3 and 1.2 clients: `tls.dial(host, port, config)` and `tls.client(sock, name,
  config)` give a `*tls.Conn` with `read`, `write`, `close`. TLS 1.3 with X25519 and
  TLS_AES_128_GCM_SHA256, TLS_AES_256_GCM_SHA384, TLS_CHACHA20_POLY1305_SHA256; TLS 1.2 with
  ECDHE (X25519, P-256, P-384) and AES-GCM or ChaCha20-Poly1305 only, the extended master secret,
  and the RFC 8446 downgrade check. SNI, ALPN, KeyUpdate; the certificate chain is verified against
  the system's roots and the host name. No session resumption, 0-RTT or client certificates.
  `docs/tls.md`.
- `std/http`'s client speaks `https://` (`ClientRequest.tls` for another `*tls.Config`).
- `std/x509`: X.509 certificates: strict DER parsing (`parse`, `parse_pem`), the system's roots
  (`system_roots`, `$SSL_CERT_FILE`), chain verification with dates, CA flags, key usage, path
  length, extended key usage and host names (`verify`, `match_hostname`). `docs/x509.md`.
- `std/pubkey`: signature verification for RSA (PKCS#1 v1.5 and PSS), ECDSA P-256/P-384 and
  Ed25519 keys given as SubjectPublicKeyInfo (`verify_signature`, `key_info`), and ECDH on P-256
  and P-384 (`ecdh_generate`, `ecdh`). `docs/pubkey.md`.
- `std/cipher`: AES-GCM (128/192/256) and ChaCha20-Poly1305 (`aes_gcm_seal`/`open`,
  `chacha20_poly1305_seal`/`open`, and `new_aes_gcm`/`new_chacha20_poly1305` for many messages
  with one key). `docs/cipher.md`.
- `std/crypto`: X25519 (`x25519`, `x25519_base`), SHA-384 (`sha384`, `new_sha384`,
  `hmac_sha384`) and HKDF (`hkdf_extract`, `hkdf_expand`).

## [0.7.0] - 2026-11-15

### Added
- `std/websocket`: WebSocket (RFC 6455). A blocking client (`dial`, `dial_with`, `read`,
  `send_text`, `send_binary`, `send_json`, `close`) with headers and subprotocols in the
  handshake, automatic answers to pings, pings to detect a dead connection, a read timeout and
  reconnection with backoff (`on_open` after each one); and a server inside `std/http`'s event
  loop (`accept`, `accept_with`, `on_message`, `on_close`, broadcasts, pings to quiet clients).
  Fragmented messages are joined; `ws://` only (no TLS). `docs/websocket.md`.
- `std/http`: protocol upgrades. `res.upgrade(h)` after a 101 hands the connection to an
  `http.StreamHandler` (`stream_open`, `stream_data`, `stream_closed`; `Stream.write`,
  `Stream.close`), served by the event loop and never closed for being idle. `http.every(ms, f)`
  runs `f` periodically inside the loop.
- `caju upgrade`: installs releases side by side in `~/.caju/versions/<version>` and switches
  `~/.caju/current` atomically. `caju upgrade [version]`, `--rollback` (back to the previous
  version, without downloading), `--list`, `--clean`, `--check`. Inside a project whose
  `caju.toml` asks for other compiler versions it asks first (`--yes` does not). Interactive
  commands check for a new release at most once a day, in the background
  (`CAJU_NO_UPDATE_CHECK=1` turns it off; never in CI or without a terminal). `docs/upgrade.md`.
- Signed releases: each package has a `.sig` (an Ed25519 signature over its version, file name
  and SHA-256). `caju upgrade` refuses packages without a valid signature from the release key
  (`--allow-unsigned` accepts older releases with only their SHA-256); `install.sh` checks it
  with `openssl`. `caju release keygen|sign|verify` (hidden) is what the release workflow uses.
- `std/crypto`: Ed25519 signatures (`ed25519_public_key`, `ed25519_sign`, `ed25519_verify`, RFC
  8032; non-canonical signatures are refused).
- `std/os`: `unix_time()` (the wall clock) and `is_terminal(fd)`.

### Changed
- `install.sh` installs into `~/.caju/versions/<version>` with `~/.caju/current` (an installation
  made by the previous installer moves there, keeping `pkg/`), checks the release signature, uses
  `curl --proto =https` and fails when it cannot compute the SHA-256 instead of skipping it.
- A package that needs another compiler version suggests `caju upgrade <version>`.

### Fixed
- The release workflow no longer expands the tag name inside its shell scripts (a crafted tag
  name could run commands).
- `caju run`, `build`, `test` and `check` of a file that does not exist say so, instead of a
  runtime error.

### Security
- `std/http` server: requests are parsed strictly and refused with 400 when a proxy could read
  them differently (request smuggling): Content-Length with Transfer-Encoding, conflicting
  Content-Lengths, a space before ":", bare CR or LF, folded lines, control bytes, a Content-Length
  that is not only digits, method names that are not tokens; other versions than HTTP/1.0 and 1.1
  get 505. Repeated headers are joined (`Cookie` with "; ") instead of the last one winning.
- `std/http` server: the body buffer grows as bytes arrive instead of reserving what
  Content-Length announces (a few hundred connections announcing 16 MB each could exhaust the
  memory). New limits: `set_max_connections` (10000), `set_max_buffered` (1 GiB for every input
  buffer together; 503 beyond), `set_request_timeout` (30 s for a whole request, against clients
  that send a byte now and then), `set_max_body` (16 MiB), `set_max_stream_backlog` (16 MiB
  queued for a stream that does not read).
- `std/http` server: header values have CR, LF and NUL turned into spaces and invalid header
  names are dropped (a value taken from the request could add headers or a body: response
  splitting). A handler that panics gets a 500 response and a line on the standard error instead
  of ending the server. Paths with `//`, `.` or `..` segments are redirected (301) to the clean
  path before routing.
- `std/http` client: a redirect to another host or port drops `Authorization`, `Cookie`,
  `Proxy-Authorization` and `Host`; a redirect that becomes a GET drops `Content-Type`. URLs,
  methods and headers with CR, LF, spaces or control bytes are refused. Responses are limited to
  `set_max_response_size` (64 MiB), 200 header lines and 10 informational responses, and bodies
  are gathered without copying everything received at each read.
- `std/websocket` server: a browser handshake is accepted only from the request's own origin, or
  from `Options.origins` (`"*"` for any), against cross-site WebSocket hijacking; 403 otherwise.
  `Sec-WebSocket-Key` must be 16 bytes in base64. Server connections ping quiet clients every
  30 s by default (`ping_interval_ms: -1` turns it off). Large frames arriving in many pieces are
  joined once.
- `std/websocket`: text messages and close reasons must be UTF-8 (1007 otherwise), close frames
  need a valid code (1002 otherwise), the client checks `Connection: Upgrade` in the answer and
  refuses headers and URLs with CR or LF, and masking keys come from the kernel's secure generator.
- `std/strings`: `valid_utf8`.
- Runtime: a string of negative or absurd length (from a bad argument, such as
  `crypto.pbkdf2_sha256` with a negative key length or `net.Conn.read` with a negative maximum)
  is a runtime error; before, it made a small block whose header claimed a huge length.
  `bytes.Buffer` checks offsets without overflowing and refuses `slice(hi < lo)` and negative
  lengths (reads and writes outside the buffer were possible).
- `std/net`: DNS replies are checked against cache poisoning: random query ids (getrandom), the
  reply must repeat the question, only the A record of the name asked for (or of its CNAME chain)
  counts, other classes are ignored, truncated replies are errors and TTLs are capped at a day.
  `net.dns_answer` parses a reply.
- `std/toml`: nesting deeper than 500 levels is an error instead of a stack overflow (a package's
  caju.toml is untrusted input).
- `caju pkg`: pre-release versions accept only `[0-9A-Za-z-]` identifiers (`1.0.0-../../x` was a
  path outside the cache); caju.lock entries need a valid name, version, `sha256:<64 hex>` hash
  and 40-hex commit; a package's `entry` must stay inside it; `caju pkg hash` refuses file names
  with control characters.
- `caju bench` writes its programs to a private temporary directory instead of a fixed name in
  /tmp. The CI workflows pin their actions by commit and CI runs with read-only permissions.
- docs/mcp.md: the risk of running `caju mcp` with assistants that read untrusted text.

## [0.6.0] - 2026-11-14

### Added
- An HTTP client in `std/http`: `get`, `head`, `post`, `post_form` and `request` (any method,
  headers, body, timeout, redirects on or off), giving a `ClientResponse` (status, headers, body,
  final URL). It keeps connections alive and reuses them, replacing one the server closed; follows
  301/302/303/307/308 redirects (up to 10); reads bodies by Content-Length, chunked or until the
  close; skips 100 Continue. Plain `http://` only: `https://` URLs are refused (no TLS yet).
  `docs/http.md`.
- `http.query_escape`, `http.query_unescape`, `http.encode_form` and `http.parse_form`.
- `net.resolve(host)`: host names to IPv4 addresses, from `/etc/hosts` and then the DNS servers of
  `/etc/resolv.conf` (A records, cached for their TTL). `net.dial` now takes names too.
- The `caju` field of `caju.toml` takes a requirement on the compiler version: a minimum
  (`"0.6.0"`, `">=0.6.0"`), `>`, `<`, `<=`, `=`, ranges (`">=0.5.0, <0.7.0"`), `^` and `~`. It is
  checked for the project and every package it uses (directly or not) by `caju pkg add`,
  `install` and `update`, and by `caju build`, `run`, `test` and `check`, with a message that
  names the package, the requirement and the running version. `caju pkg init` writes
  `caju = ">=<current version>"`. See docs/packages.md.
- `net.dial_timeout(host, port, ms)`, `Conn.set_timeout(ms)` (reads and writes that wait longer
  fail with "timed out") and `Conn.readable()`.

### Changed
- The compiler requirement of `caju.toml` is checked for the project itself too, and also when
  `caju.lock` is already up to date (before, only dependencies were checked, and only while
  resolving them).

### Fixed
- Slicing a `str` (`s[a:b]`) keeps the bytes as they are. It used to replace bytes that are not
  UTF-8 with U+FFFD, which corrupted binary data (network protocols, compressed data) and could
  change the length of a substring cut in the middle of a character. Slicing is also about 7×
  faster, since it no longer validates the bytes.
- `string([]byte)` keeps the bytes as they are too, instead of replacing the ones that are not
  UTF-8 with U+FFFD: binary data converted to bytes and back comes out unchanged.

## [0.5.0] - 2026-11-12

### Added
- `std/cli`: command line programs. Commands and nested subcommands, bool/str/int/list flags
  (short and long forms, choices, required, environment variables, defaults), required, optional
  and variadic arguments, generated help (`-h`, `--help`, `help <command>`), `--version`, and
  errors with suggestions for misspelled names (`docs/cli.md`).
- `caju mcp`: a Model Context Protocol server for AI assistants, with the tools `caju_check`,
  `caju_run`, `caju_test`, `caju_docs` and `caju_reference` (`docs/mcp.md`).
- `caju check [--json] file.caju`: type-checks without generating code; with `--json`, the
  diagnostics with file, line, column and stage.
- A code graph in `caju mcp`, kept in memory and updated incrementally: `caju_find`,
  `caju_symbol`, `caju_related`, `caju_outline`, `caju_call_path` and `caju_graph_stats` answer
  where a symbol is, its signature, callers, callees, implementations and call chains in a few
  lines, so an assistant doesn't read whole files (`docs/mcp.md`).
- `caju pkg cache list|verify|clean|dir`: the package cache shared by every project on the
  machine. Each download records its commit and SHA-256 hash; a cached copy is reused by any
  project only if its files still have that hash, and a changed copy is downloaded again.
- `caju_pkg` in `caju mcp`: add, remove, install, update and verify packages, and list the cache.
- `os.read_line()`: one line of the standard input at a time.
- `docs/language.md`: the language reference, also in the release package with `docs/mcp.md`.
- WebAssembly modules carry a `name` section (function names in stack traces and profiles);
  `tools/wasm/disasm.mjs` prints the instructions of a function by name.
- `dump_main --stage=lex` prints the tokens of a file.

### Changed
- The `caju` command line is declared with `std/cli`: every command has `--help`, misspelled
  commands and flags get a suggestion, `--target` values are checked, and `caju bench --runs`
  also takes `--runs N`. Usage errors exit with 2.
- `caju pkg cache` alone lists the cache (as `caju pkg cache list`).
- The release chain starts with the JavaScript compiler building `compiler/build_main.caju`,
  which builds the whole compiler (the JS compiler lacks std/json's reflection intrinsics).
- `caju pkg install`/`add`/`update` replace a changed cached package with a new download instead
  of failing; `caju pkg update` prints the version changes after the downloads.
- The documentation is in English (README, docs/, bench notes, CLAUDE.md); docs with Portuguese
  names were renamed: native-architecture.md, native-compiler-plan.md, history.md.
- Release notes come from this changelog (`tools/changelog.sh`).
- WebAssembly: no default epilogue after a function's final `return` (smaller code).

## [0.4.0] - 2026-11-12

### Added
- WebAssembly target: `caju build --target wasm` compiles a program and the runtime to a wasm
  module (`compiler/wasm.caju`, `compiler/wasmenc.caju`, `rt/wasm.caju`). Values, the stack in
  memory and the calling convention follow the native ones, so the runtime and the garbage
  collector work unchanged; `recover` uses wasm exceptions.
- The compiler compiles itself to `caju.wasm`, and `caju.wasm` compiles itself to the same bytes.
- `caju-wasm.tar.gz` in every release: the compiler in WebAssembly, the standard library and the
  runtime (`caju-files.json`), `caju-host.mjs` (the Linux system calls of a program in wasm) and
  `caju-browser.mjs` (`loadCaju()`: compile and run in a browser over an in-memory file system).
  The playground of https://cajulang.vercel.app uses it.
- `tools/wasm/run.mjs` runs a wasm program in Node over the real file system.
- `caju test --target wasm`: the test suite with the programs compiled to wasm.

### Changed
- `os.run` first asks the host to run the program (a WebAssembly host has no `fork`); on Linux
  the call answers ENOSYS and the usual `fork`/`execve` path runs.
- The size of the collector's arena comes from the system part of the runtime
  (`rt_os_arena_size`: 16 GB on Linux and Windows, 2 GB in wasm).
- Faster maps with text keys (index up to 3/4 full, 8-byte text hashing and equality), `std/json`
  (flat structs by leaf functions, one-pass checks, reused tables) and `std/http` routing (no
  hashing). The benchmarks were measured again (`bench/compare/RESULTS.md`).
- The repository moved to github.com/cajulang/cajulang.

### Fixed
- `lib/http_test.caju` waits for the test server by time (20 s) instead of by a number of tries.

## [0.3.0] - 2026-11-11

### Added
- `std/http`: an event loop with epoll, keep-alive, pipelining and `listen_and_serve_workers`
  (several processes with `SO_REUSEPORT`).
- HTTP benchmark against Gin and Go's net/http (`bench/http`).

### Changed
- Faster `std/json`: an encoding plan per struct, its own buffer and direct decoding.
- Allocator without free lists: runs of free slots per size class (and per "no pointers").
- Fewer allocations per request: maps in one block, literals without `rt_zero`, HTTP responses
  without concatenation.

## [0.2.0] - 2026-11-11

### Added
- `std/json`: `marshal`, `marshal_indent`, `unmarshal`, `parse`, `valid` and `quote`, in the style
  of Go's encoding/json.

## [0.1.0] - 2026-11-11

### Added
- First release: the language, the native compiler for x86-64 (ELF on Linux, PE on Windows)
  written in Caju and compiling itself (stage 2 = stage 3), the runtime and garbage collector in
  Caju, the standard library (strings, strconv, math, bytes, os, fs, path, net, http, toml,
  crypto, hash, hex, base64, testing), `caju test` with BDD-style tests and the package manager
  `caju pkg` (GitHub repositories, minimal version selection, `caju.lock` with SHA-256 hashes).
- An optimizing code generator: registers for locals and arguments, XMM registers for floats,
  versioned and vectorized loops, division by constants, inlining, accumulator loops for
  self-recursion.
- Benchmark against Go, Rust and Python (`bench/compare`).
- Release package, installer (`install.sh`) and GitHub workflows. MIT license.

[Unreleased]: https://github.com/cajulang/cajulang/compare/v0.9.1...HEAD
[0.9.1]: https://github.com/cajulang/cajulang/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/cajulang/cajulang/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/cajulang/cajulang/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/cajulang/cajulang/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/cajulang/cajulang/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/cajulang/cajulang/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/cajulang/cajulang/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/cajulang/cajulang/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/cajulang/cajulang/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/cajulang/cajulang/releases/tag/v0.1.0
