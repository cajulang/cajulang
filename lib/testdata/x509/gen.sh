#!/bin/sh
# Regenerates the Ed25519 test certificates of lib/x509_test.caju (OpenSSL 3).
# The private keys are thrown away; only the PEM certificates are kept.
# Running it again changes every certificate, so the dates checked in the tests must follow.
set -e
cd "$(dirname "$0")"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

key() { openssl genpkey -algorithm ed25519 -out "$T/$1.key" 2>/dev/null; }

# self-signed root: name, subject
root() {
  key "$1"
  cat > "$T/$1.ext" <<X
[v3]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
X
  openssl req -x509 -new -key "$T/$1.key" -subj "$2" -days 36500 -set_serial 1 \
    -config "$T/$1.ext" -extensions v3 -out "$1.pem" 2>/dev/null
}

# cert signed by an issuer: name, subject, issuer, extension lines (one per argument after 3)
signed() {
  name=$1; subj=$2; iss=$3; shift 3
  key "$name"
  printf '[v3]\nsubjectKeyIdentifier = hash\nauthorityKeyIdentifier = keyid\n' > "$T/$name.ext"
  for l in "$@"; do printf '%s\n' "$l" >> "$T/$name.ext"; done
  openssl req -new -key "$T/$name.key" -subj "$subj" -out "$T/$name.csr" 2>/dev/null
  openssl x509 -req -in "$T/$name.csr" -CA "$iss.pem" -CAkey "$T/$iss.key" -days 36500 \
    -set_serial "0x$(openssl rand -hex 8)" -extfile "$T/$name.ext" -extensions v3 -out "$name.pem" 2>/dev/null
}

CA='basicConstraints = critical, CA:TRUE'
CA0='basicConstraints = critical, CA:TRUE, pathlen:0'
KU_CA='keyUsage = critical, keyCertSign, cRLSign'
KU_LEAF='keyUsage = critical, digitalSignature'
EKU='extendedKeyUsage = serverAuth'
SAN='subjectAltName = DNS:example.test, DNS:www.example.test, DNS:*.wild.example.test, IP:127.0.0.1, IP:::1'

root root "/C=BR/O=Caju Test/CN=Caju Test Root"
signed inter "/C=BR/O=Caju Test/CN=Caju Test Intermediate" root "$CA0" "$KU_CA"
signed leaf "/O=Caju Test/CN=example.test" inter "$KU_LEAF" "$EKU" "$SAN"

# a leaf from a root nobody trusts
root evil_root "/O=Evil/CN=Evil Root"
signed evil_leaf "/CN=example.test" evil_root "$KU_LEAF" "$EKU" "$SAN"

# an intermediate without the CA flag, and a leaf it signed
signed noca_inter "/O=Caju Test/CN=Not A CA" root 'basicConstraints = critical, CA:FALSE' "$KU_CA"
signed noca_leaf "/CN=example.test" noca_inter "$KU_LEAF" "$EKU" "$SAN"

# pathlen:0 broken: inter (pathlen 0) -> sub (CA) -> leaf
signed sub_inter "/O=Caju Test/CN=Sub Intermediate" inter "$CA" "$KU_CA"
signed sub_leaf "/CN=example.test" sub_inter "$KU_LEAF" "$EKU" "$SAN"

# a leaf with an unknown critical extension
signed crit_leaf "/CN=example.test" inter "$KU_LEAF" "$EKU" "$SAN" '1.3.6.1.4.1.99999.1 = critical, ASN1:UTF8String:hello'

# a leaf only good for client authentication
signed client_leaf "/CN=example.test" inter "$KU_LEAF" 'extendedKeyUsage = clientAuth' "$SAN"

# an intermediate with name constraints
signed nc_inter "/O=Caju Test/CN=Constrained" root "$CA" "$KU_CA" 'nameConstraints = critical, permitted;DNS:example.test'
signed nc_leaf "/CN=example.test" nc_inter "$KU_LEAF" "$EKU" "$SAN"

# an intermediate whose keyUsage lacks keyCertSign
signed noku_inter "/O=Caju Test/CN=No Cert Sign" root "$CA" 'keyUsage = critical, digitalSignature'
signed noku_leaf "/CN=example.test" noku_inter "$KU_LEAF" "$EKU" "$SAN"

# a leaf without SANs (only a CN)
signed cn_leaf "/CN=example.test" inter "$KU_LEAF" "$EKU"

# RSASSA-PSS (SHA-384) self-signed, for the algorithm mapping only (parsed, not verified here)
openssl req -x509 -newkey rsa:2048 -keyout "$T/pss.key" -nodes -subj "/CN=PSS Test" -days 36500 \
  -sha384 -sigopt rsa_padding_mode:pss -sigopt rsa_pss_saltlen:48 -out pss.pem 2>/dev/null
