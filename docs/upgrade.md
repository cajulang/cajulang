# Upgrading caju

`caju upgrade` installs other releases of the compiler next to the current one and switches
between them; nothing is overwritten in place.

```
~/.caju/                          $CAJU_HOME
  versions/0.6.0/  0.7.0/         one directory per installed release (bin/caju, lib/, rt/, ...)
  current -> versions/0.7.0       the active one
  previous                        the one active before the last switch
  pkg/                            the package cache (shared by every version, never touched)
  update-check                    the last check for a new release
~/.local/bin/caju -> ~/.caju/current/bin/caju     ($CAJU_BIN_DIR)
```

```sh
caju upgrade                 # the latest release
caju upgrade 0.6.0           # a given version (downloaded only if it is not installed)
caju upgrade --rollback      # back to the previous version, without downloading
caju upgrade --list          # the installed versions (* active)
caju upgrade --clean         # remove every version except the active and the previous one
caju upgrade --check         # only say whether a newer release exists
```

The switch is atomic: `current` is a symbolic link replaced with `rename`, so a command running at
that moment uses either the old version or the new one. An installation made by the old
`install.sh` (the release spread over `~/.caju`) moves to `versions/<its version>/` the first time.

## Signatures

Each release has, next to every package, `<package>.sig`:

```
caju-release 1
version 0.7.0
file caju-linux-x86_64.tar.gz
sha256 <hex>
key <hex of the public key>
signature <hex>                   Ed25519 over every line above
```

`caju upgrade` installs a package only if that manifest is signed by one of the release keys built
into it, names the version and file it asked for (an older signed package cannot be passed off
as a newer one), and has the SHA-256 of the bytes downloaded. Then it unpacks the package, refuses
anything that is not a regular file or directory, and runs the new `bin/caju version` to check that
it is the version asked for. Releases from before signing (0.6.0 and older) have no `.sig`:
`--allow-unsigned` installs them checking only their SHA-256, which comes from the same release.

`install.sh` checks the same signature with `openssl` (1.1.1 or newer); without `openssl` it checks
only the SHA-256 listed in the signature and warns (`CAJU_REQUIRE_SIGNATURE=1` makes that an error).

## Projects that ask for a version

When the `caju.toml` of the current directory (or a parent) has `caju = ">=0.6.0, <0.7.0"` and the
version being activated does not satisfy it, `caju upgrade` says so and asks for confirmation;
`--yes` switches without asking, and without a terminal it refuses. The compiler is global: other
projects use whichever version is active.

## The daily check

`caju build`, `run`, `test`, `check`, `pkg` and `version`, when run in a terminal, look at
`~/.caju/update-check`. Once a day they start `caju upgrade --check` in the background (the
command itself does not wait), and if the last check found a newer release they print, at most
once a day:

```
caju 0.7.0 is available (this is 0.6.0): caju upgrade
```

No check runs when `CAJU_NO_UPDATE_CHECK` or `CI` is set, or when the standard error is not a
terminal (scripts, pipes, editors). The check runs `git ls-remote` on the compiler's repository
and sends nothing else.

## Mirrors and tests

`CAJU_UPGRADE_SOURCE=<directory>` takes releases from `<directory>/v<version>/<files>` instead of
GitHub; with it, `CAJU_UPGRADE_KEY=<hex>` trusts one more public key (`compiler/upgrade_test.caju`
uses both). Neither changes anything without the other.
