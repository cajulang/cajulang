#!/bin/sh
# Installs Caju from the GitHub releases.
#
#   curl -fsSL https://raw.githubusercontent.com/cajulang/cajulang/main/install.sh | sh
#
# Versions are installed side by side and `caju upgrade` switches between them afterwards:
#   $CAJU_HOME/versions/<version>/       bin/caju, lib/, rt/, examples/, docs/
#   $CAJU_HOME/current -> versions/<version>
#   $CAJU_BIN_DIR/caju -> $CAJU_HOME/current/bin/caju
#
# Releases are signed with the Caju release key (Ed25519, release_keys below): the installer
# checks the signature with openssl when it is available, and the SHA-256 of the package always.
#
# Environment:
#   CAJU_VERSION=0.7.0          a given version (default: the latest release)
#   CAJU_HOME=~/.caju           where the versions go (the package cache, pkg/, stays there too)
#   CAJU_BIN_DIR=~/.local/bin   where the `caju` command is linked
#   CAJU_PACKAGE=file.tar.gz    install from a local package (and its .sig, if next to it)
#   CAJU_REQUIRE_SIGNATURE=1    fail instead of warning when the signature cannot be checked
#   CAJU_ALLOW_UNSIGNED=1       accept a release older than signing (only its SHA-256)
set -eu

repo="cajulang/cajulang"
home="${CAJU_HOME:-$HOME/.caju}"
bin_dir="${CAJU_BIN_DIR:-$HOME/.local/bin}"
asset="caju-linux-x86_64.tar.gz"
# the public release keys (hex), the same as RELEASE_KEYS in compiler/upgrade.caju; another key
# may be trusted for a local package (CAJU_PACKAGE) only
release_keys=""
if [ -n "${CAJU_PACKAGE:-}" ] && [ -n "${CAJU_RELEASE_PUBKEY:-}" ]; then
  release_keys="$release_keys $CAJU_RELEASE_PUBKEY"
fi

fail() { echo "caju install: $*" >&2; exit 1; }
warn() { echo "caju install: warning: $*" >&2; }

case "$(uname -s)" in
  Linux) ;;
  *) fail "only Linux x86-64 has a package for now (on Windows, use WSL)" ;;
esac
case "$(uname -m)" in
  x86_64|amd64) ;;
  *) fail "only x86-64 is supported (this machine is $(uname -m))" ;;
esac

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fetch() {  # url dest
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL --proto '=https' --tlsv1.2 "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --https-only "$1" -O "$2"
  else
    fail "needs curl or wget"
  fi
}

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" | cut -d' ' -f1
  elif command -v openssl >/dev/null 2>&1; then openssl dgst -sha256 -r "$1" | cut -d' ' -f1
  else fail "needs sha256sum, shasum or openssl to check the package"
  fi
}

# writes the bytes of a hex string to a file
hex_to_file() {
  printf "$(printf '%s' "$1" | awk 'BEGIN { for (i = 0; i < 16; i++) h[sprintf("%x", i)] = i }
    { s = tolower($0); for (i = 1; i < length(s); i += 2) printf "\\%03o", h[substr(s, i, 1)] * 16 + h[substr(s, i + 1, 1)] }')" > "$2"
}

# the value of a line "<key> <value>" of the signature file
field() { sed -n "s/^$1 //p" "$tmp/$asset.sig" | head -n 1; }

# checks $tmp/$asset against $tmp/$asset.sig
check_signature() {
  [ "$(sed -n 1p "$tmp/$asset.sig")" = "caju-release 1" ] || fail "not a caju release signature"
  [ "$(field file)" = "$asset" ] || fail "the signature is for $(field file), not $asset"
  [ "$(field sha256)" = "$(sha256 "$tmp/$asset")" ] || fail "the package does not match its signature (SHA-256 differs)"
  key=$(field key)
  trusted=""
  for k in $release_keys; do [ "$k" = "$key" ] && trusted=1; done
  if [ -z "$trusted" ]; then
    if [ -z "$release_keys" ]; then
      [ -n "${CAJU_REQUIRE_SIGNATURE:-}" ] && fail "this installer has no release key to check the signature with"
      warn "this installer has no release key yet; only the SHA-256 in the signature file was checked"
      return 0
    fi
    fail "the release is signed by a key this installer does not trust ($key)"
  fi
  if command -v openssl >/dev/null 2>&1; then
    sed '/^signature /,$d' "$tmp/$asset.sig" > "$tmp/body"
    hex_to_file "$(field signature)" "$tmp/sig.bin"
    hex_to_file "302a300506032b6570032100$key" "$tmp/key.der"
    openssl pkey -pubin -inform DER -in "$tmp/key.der" -out "$tmp/key.pem" 2>/dev/null || fail "openssl cannot read the release key (needs OpenSSL 1.1.1 or newer)"
    openssl pkeyutl -verify -pubin -inkey "$tmp/key.pem" -rawin -in "$tmp/body" -sigfile "$tmp/sig.bin" >/dev/null 2>&1 ||
      fail "invalid signature: the release files were changed after signing"
  else
    [ -n "${CAJU_REQUIRE_SIGNATURE:-}" ] && fail "openssl is needed to check the signature"
    warn "openssl not found: the signature was not checked, only the SHA-256 it lists"
  fi
}

if [ -n "${CAJU_PACKAGE:-}" ]; then
  cp "$CAJU_PACKAGE" "$tmp/$asset"
  [ -f "$CAJU_PACKAGE.sig" ] && cp "$CAJU_PACKAGE.sig" "$tmp/$asset.sig"
else
  if [ -n "${CAJU_VERSION:-}" ]; then
    url="https://github.com/$repo/releases/download/v${CAJU_VERSION#v}/$asset"
  else
    url="https://github.com/$repo/releases/latest/download/$asset"
  fi
  echo "Downloading $url"
  fetch "$url" "$tmp/$asset" || fail "download failed"
  fetch "$url.sig" "$tmp/$asset.sig" 2>/dev/null || rm -f "$tmp/$asset.sig"
  if [ ! -f "$tmp/$asset.sig" ]; then
    fetch "$url.sha256" "$tmp/$asset.sha256" || fail "checksum download failed"
  fi
fi

signed_version=""
if [ -f "$tmp/$asset.sig" ]; then
  check_signature
  signed_version=$(field version)
elif [ -n "${CAJU_ALLOW_UNSIGNED:-}" ] || [ -n "${CAJU_PACKAGE:-}" ]; then
  if [ -f "$tmp/$asset.sha256" ]; then
    [ "$(cut -d' ' -f1 "$tmp/$asset.sha256")" = "$(sha256 "$tmp/$asset")" ] || fail "checksum does not match"
  fi
  warn "this package is not signed"
else
  fail "the release has no signature (older than signing); CAJU_ALLOW_UNSIGNED=1 installs it checking only its SHA-256"
fi

mkdir -p "$tmp/x"
tar -C "$tmp/x" --no-same-owner -xzf "$tmp/$asset" || fail "could not extract the package"
src=$(find "$tmp/x" -mindepth 1 -maxdepth 1)
{ [ "$(printf '%s\n' "$src" | wc -l)" -eq 1 ] && [ -d "$src" ] && [ -x "$src/bin/caju" ]; } || fail "unexpected package layout"
[ -z "$(find "$src" ! -type f ! -type d)" ] || fail "the package has entries that are not files or directories"
version=$(env -u CAJU_ROOT "$src/bin/caju" version | sed -n 's/^caju //p')
[ "$(basename "$src")" = "caju-$version" ] || fail "the package says it is caju $version, inside $(basename "$src")"
if [ -n "$signed_version" ] && [ "$signed_version" != "$version" ]; then
  fail "the signature is for version $signed_version, not $version"
fi

mkdir -p "$home/versions"
# an installation made by an older installer (the release spread over $CAJU_HOME) moves to versions/
if [ -f "$home/bin/caju" ] && [ ! -L "$home/bin/caju" ]; then
  old=$(env -u CAJU_ROOT "$home/bin/caju" version 2>/dev/null | sed -n 's/^caju //p')
  if [ -n "$old" ] && [ ! -e "$home/versions/$old" ]; then
    mkdir -p "$home/versions/$old"
    for n in bin lib rt examples docs README.md CHANGELOG.md LICENSE; do
      if [ -e "$home/$n" ]; then mv "$home/$n" "$home/versions/$old/"; fi
    done
    ln -sfn "versions/$old" "$home/current"
  fi
fi

rm -rf "$home/versions/$version"
mv "$src" "$home/versions/$version"
previous=""
[ -L "$home/current" ] && previous=$(basename "$(readlink "$home/current")")
if [ -n "$previous" ] && [ "$previous" != "$version" ]; then
  echo "$previous" > "$home/previous"
fi
rm -f "$home/current.new"
ln -s "versions/$version" "$home/current.new"
mv -T "$home/current.new" "$home/current"

mkdir -p "$bin_dir"
ln -sf "$home/current/bin/caju" "$bin_dir/caju"

echo "Installed caju $version in $home/versions/$version"
case ":$PATH:" in
  *":$bin_dir:"*) echo "Run: caju run $home/current/examples/hello-world.caju" ;;
  *) echo "Add $bin_dir to your PATH, e.g.:"
     echo "  echo 'export PATH=\"$bin_dir:\$PATH\"' >> ~/.bashrc && . ~/.bashrc" ;;
esac
