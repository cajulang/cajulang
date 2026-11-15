# Platform matrix

What each feature of the language, its standard library and the `caju` command does on each
target. `linux` and `windows` are native x86-64 executables (`caju build`, `caju build --target
windows`); `wasm` is `caju build --target wasm`, run by the host in `tools/wasm/caju-host.mjs`,
either in Node (`tools/wasm/run.mjs`, over the real file system, with `os.run` and the standard
input) or in a browser page's worker (`tools/wasm/caju-browser.mjs`: an in-memory file system, no
processes, no standard input). The compile-time refusals are explained in
[platforms.md](platforms.md).

Legend:

- **works**: does what the documentation says, the same way as on Linux.
- **emulated**: works, through the WebAssembly host imitating a Linux call (details in the note).
- **refused**: a program that can reach it does not build: a "Platform error" with the chain of
  calls (or "not supported yet" for what the language has not implemented on any target).
- **error**: builds, and at run time returns an `error` (or prints a message and exits): the
  program can tell.
- **broken**: builds and misbehaves at run time without saying so. Every one is a bug; the ones
  found while writing this page are fixed (the "was" notes) and none is left.
- **n/a**: makes no sense on that target.

This page describes Caju after the fixes of the [Unreleased] section of CHANGELOG.md.

## Built-ins and the language

| Feature | linux | windows | wasm (Node) | wasm (browser) |
|---|---|---|---|---|
| `print` (standard output, buffered) | works | works (UTF-8 console code page) | works | works (the `stdout` callback) |
| `panic`, runtime errors | works: message on the standard output, exit code 1 | works, same | works, same | works, same; a JS stack overflow becomes "too much recursion for this browser's stack" |
| `len`, `append`, `make`, maps, closures, `defer`/`recover`, interfaces, `any` | works | works | works | works |
| `alloc`, `free`, `peek8/16/32/64`, `poke8/16/32`, `readstr`, `readwstr` | refused | works | refused | refused |
| `extern` DLL calls | refused (only if reachable) | works | refused (only if reachable) | refused (only if reachable) |
| `dllexport`, building a DLL | n/a | not yet (builds an executable) | n/a | n/a |
| `go`, `chan`, `select` | refused ("not supported yet", phase 6) | refused | refused | refused |
| `sleep` | not part of the language since 0.9.0: `os.sleep` | | | |

Was: `alloc`/`peek`/`poke`/`readstr`/`readwstr` were "not supported yet" on every target, even
Windows, the only one where they make sense; now Windows implements them (HeapAlloc, UTF-16
conversion) and the other targets refuse them with a Platform error. An `extern` call was refused
on Linux and WebAssembly even in a function nothing called; now only a reachable one is. The
platform pass skipped programs made of a single file (no imports) entirely.

## Intrinsics the standard library uses

Only the runtime and `std/` may call them. The first group is plain code; the second asks the
system for something, and each runtime (rt/linux.caju, rt/windows.caju, rt/wasm.caju) does it its
own way (`types.RT_INTRINSICS`).

| Intrinsic | linux | windows | wasm (Node) | wasm (browser) |
|---|---|---|---|---|
| `__load*`, `__store*`, `__strp`, `__pstr`, `__newstr`, `__flush`, `__exit`, `__anyp`, `__pany`, `__alloc`, `__zero`, `__make_slice`, `__map_new`, `__map_set`, `__sqrt`, `__fmod` | works | works | works | works |
| `__argp` (arguments and environment) | works (the process stack) | works (CommandLineToArgvW and GetEnvironmentStringsW, converted to UTF-8 in Linux's layout) | works (the host writes them) | works (the `args` given to `run`; environment `HOME=/work`) |
| `__sleep` | works (nanosleep) | works (Sleep) | works (Atomics.wait) | works: blocks the program's worker (Atomics.wait; a busy wait without cross-origin isolation, which freezes a page if the program runs outside a worker) |
| `__nanotime`, `__unix_nano` | works (clock_gettime) | works (QueryPerformanceCounter, GetSystemTimeAsFileTime) | works (performance.now, Date.now) | works (same; millisecond resolution or coarser) |
| `__random` | works (getrandom) | works (BCryptGenRandom) | works (crypto.getRandomValues, in 64 KB pieces) | works (same) |
| `__write` (fd 1, 2) | works | works (WriteFile on the standard handles) | works | works (the `stdout`/`stderr` callbacks) |
| `__read` (fd 0) | works | works (ReadFile; a closed pipe is the end) | works | works: always the end of the input (no `stdin`) |
| `__isatty` | works (TCGETS) | works (GetConsoleMode) | works (tty.isatty, run.mjs) | works: always false |
| `__syscall` | works | refused (the function that uses it) | emulated: the calls the host knows (files, clocks, getrandom, mmap...), ENOSYS for the rest | emulated, same, over the in-memory file system |

Was: `os.args`, `os.environ`, `os.getenv` and `os.lookup_env` built for Windows and crashed when
called (`__argp` was 0 there; exit code 5). `os.nanotime`, `os.unix_time`, `os.stdout`,
`os.stderr`, `os.eprintln`, `os.read_line`, `os.read_stdin`, `os.is_terminal` and
`crypto.random_bytes` used `__syscall`, so Windows refused them although its runtime could do
them. `CAJU_SKIP_SLEEP=0` (which the browser host sets) made `os.sleep` return at once: the runtime
only looked for the variable, not its value; now only `CAJU_SKIP_SLEEP=1` skips. A
`crypto.random_bytes(n)` above 65536 bytes failed in WebAssembly (getRandomValues' limit).

## The standard library

| Module / functions | linux | windows | wasm (Node) | wasm (browser) |
|---|---|---|---|---|
| `os.args`, `os.environ`, `os.getenv`, `os.lookup_env` | works | works | works | works (what the page passes) |
| `os.exit` (flushes `print`) | works | works | works | works (the exit code of `run`) |
| `os.stdout`, `os.stderr`, `os.eprintln` | works | works | works | works |
| `os.read_line`, `os.read_stdin` | works | works | works | works: no input (`read_line` gives false) |
| `os.nanotime`, `os.unix_time`, `os.unix_nano` | works | works | works | works |
| `os.sleep` | works (0 to 30 s; `CAJU_SKIP_SLEEP=1` under `caju test`) | works | works | works (blocks the worker) |
| `os.is_terminal` | works | works | works | works: false |
| `os.read_file`, `os.write_file`, `os.exists`, `os.remove`, `os.mkdir`, `os.getwd` | works | refused | emulated (Node's file system) | emulated (in-memory, /work) |
| `std/fs` (stat, read_dir, mkdir_all, walk, glob, temp_dir, symlinks...) | works | refused | emulated | emulated (`temp_dir` needs a /tmp the page creates, or a dir) |
| `os.getpid` | works | refused | emulated: always 1 | emulated: always 1 |
| `os.executable` | works | refused | emulated: `/caju/bin/caju` (the host's path for the compiler) | emulated, same |
| `os.run` | works (fork, execve) | refused | emulated (the host's `spawn`: spawnSync) | error ("function not implemented") |
| `os.exec`, `os.exec_bytes` | works | refused | error ("function not implemented") | error |
| `crypto.random_bytes` (and so `crypto.ed25519_generate`, `pubkey.ecdh_generate`...) | works | works | works | works |
| `std/net`, `std/http` (server and client), `std/websocket`, `std/tls` | works | refused | refused | refused |
| `http.query_escape`, URL and header helpers that make no calls | works | works | works | works |
| `std/json`, `std/toml`, `std/crypto` (hashes, HMAC, HKDF, PBKDF2, Ed25519, X25519), `std/cipher`, `std/pubkey`, `std/x509` parsing and verification, `std/hash`, `std/hex`, `std/base64`, `std/strings`, `std/strconv`, `std/bytes`, `std/math`, `std/path` | works (pure code) | works | works | works |
| `x509.system_roots` | works | refused (reads the Linux CA files) | emulated (reads them through Node) | error (no such file) |
| `std/cli` (arguments, help, exit codes) | works | works | works | works |
| `std/testing` (`describe`/`it`/`expect`) | works | works | works | works |
| `std/testing` `run_file`, `run_source` | works | refused (`os.run`) | emulated | error |

## caju-ui (github.com/cajulang/ui)

| Feature | linux | windows | wasm (Node) | wasm (browser) |
|---|---|---|---|---|
| components, JSX, server rendering (`ui.render_to_string`, `ui.page`) | works | works | works | works |
| `ui.mount`, `ui.hydrate` (the `/dev/ui` device) | error: "no page to render into", exit 1 | refused (`os.read_file`) | error, same | works (in the `caju-ui` host) |
| page functions (`ui.call`, `ui.fetch`, `ui.navigate`, `ui.eth.*`), `ui.on_page_event` | n/a: do nothing on the server | n/a | n/a | works |

## The caju command

`caju` itself is built for Linux (the release) and for WebAssembly (`tools/wasm/package.sh`,
`caju.wasm`, which compiles itself to the same bytes). It cannot be built for Windows: it reads
files and runs processes (`std/os`, `std/fs`), which Windows does not have in the standard
library yet.

| Command | linux | windows | wasm (Node, `caju.wasm` with run.mjs) | wasm (browser, caju-browser.mjs) |
|---|---|---|---|---|
| `caju build` (any target) | works | refused (the compiler does not build for Windows) | works | works (what the playground calls) |
| `caju run` | works (exec_bytes of the image in memory) | refused | error ("function not implemented": no exec) | error, same |
| `caju test` | works | refused | not supported (use the native `caju test --target wasm`, which runs each test in Node) | error (no processes) |
| `caju check`, `caju mcp` | works | refused | works (standard input and output) | n/a (no input) |
| `caju pkg` | works (git) | refused | emulated (git through `spawn`) | error (no processes) |
| `caju upgrade` | works (git, curl) | refused | n/a (it would replace caju.wasm's host path) | n/a |
| `caju version` | works | refused | works | works |

## Still open (proposed, not done)

- Move `alloc`/`free`/`peek*`/`poke*`/`readstr`/`readwstr` out of the language core into a
  standard module for Windows FFI (for example `std/ffi` or `std/windows`), as was done for
  `sleep`. They are only useful next to `extern`, and only Windows has them. That is a breaking
  change (a program would `import "std/ffi"` and call `ffi.alloc`), so it waits for the owner.
- Files, directories and processes on Windows (CreateFileW, FindFirstFileW, CreateProcessW) behind
  intrinsics like the ones above, so `std/os` and `std/fs` and then the `caju` command itself build
  for Windows.
- Panic and runtime error messages go to the standard output on every target (consistent, but
  unusual: most languages use the standard error).
- `os.executable` in WebAssembly answers the host's path for the compiler; a host option for the
  program's own name would be more honest.
