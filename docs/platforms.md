# Platforms

Caju compiles for `linux` (x86-64), `windows` (x86-64) and `wasm` (WebAssembly, in Node or a
browser). Not everything runs everywhere: sockets exist only on Linux (the WebAssembly host has
none, and the Windows runtime does not have them yet); files and processes use Linux system
calls, which the WebAssembly host emulates and Windows does not have; DLL calls (`extern`) and raw
memory (`alloc`, `peek`...) exist only on Windows. Instead of a program that builds and then fails
when it runs, the compiler refuses it:

```
$ caju build --target wasm app.caju
Platform error in app.caju, line 3: net.dial_timeout (std/net) is not available when compiling
for wasm: it runs on linux (declared in its header). Called through load_prices → http.get →
http.request → http.round_trip → net.dial_timeout.
```

## Only what the program can reach

After type checking, the compiler follows the functions the program can reach from the top-level
code of its modules: calls, method calls, function values, and interface calls (to the methods of
the types that reachable code constructs). A module that is imported but whose restricted
functions are never called costs nothing: a WebAssembly program may use `http.query_escape` or
`path.join`; it may not call `http.get`.

## Declaring where code runs

A comment line in the header of a file (before its first declaration) covers the whole file:

```caju
# caju:platforms linux
# (sockets and epoll)
```

The same line in the comment just above a function covers that function only, and wins over the
file's:

```caju
# caju:platforms linux wasm
export fn read_config() -> str { ... }
```

A package can declare its targets in `caju.toml` (every file of the package):

```toml
[package]
name = "github.com/acme/native-thing"
platforms = ["linux"]
```

The targets are `linux`, `windows` and `wasm`; words after them on the line are a note. With no
declaration, code runs everywhere, except that:

- on `windows`, a function that makes a Linux system call (`__syscall`) is not available;
- on `linux` and `wasm`, a call to an `extern` function (a Windows DLL) and the raw-memory
  built-ins `alloc`, `free`, `peek8/16/32/64`, `poke8/16/32`, `readstr` and `readwstr` are not
  available.

What the standard library needs from the system on every target (the arguments and environment,
the standard input and output, the clocks, `os.sleep`, `os.is_terminal`, `crypto.random_bytes`)
goes through intrinsics that each runtime implements its own way (`__nanotime`, `__unix_nano`,
`__random`, `__write`, `__read`, `__isatty`, `__sleep`: Linux system calls, kernel32 and bcrypt on
Windows, the host in WebAssembly), so those functions are not refused anywhere.

What the standard library declares today:

| | linux | wasm | windows |
|---|---|---|---|
| `std/net` (and so `std/http`'s server and client, `std/websocket`, `std/tls`) | yes | no | no |
| files and processes (`os.read_file`, `os.run`, `std/fs`...) | yes | yes (emulated by the host) | no |
| arguments, environment, standard streams, clocks, `os.sleep`, `os.is_terminal`, `crypto.random_bytes` | yes | yes | yes |
| `extern` DLL calls and raw memory (`alloc`, `peek`, `poke`, `readstr`...) | no | no | yes |
| everything else (`strings`, `json`, `crypto` hashes, `path.join`...) | yes | yes | yes |

The full picture, function by function and command by command, is in
[platform-matrix.md](platform-matrix.md).

## Tests

`caju test --target wasm` skips a test file that needs another platform, with the reason, instead
of failing it. A test file can declare its own platforms in its header.
