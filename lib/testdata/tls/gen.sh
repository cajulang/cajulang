#!/bin/sh
# Test certificates for lib/tls_test.caju (OpenSSL 3): a root CA (ECDSA P-256) and leaves for
# localhost / 127.0.0.1 with ECDSA P-256, RSA-2048 and Ed25519 keys. Valid for 100 years. The
# private keys of the leaves stay here (the test server needs them); they protect nothing.
set -eu
cd "$(dirname "$0")"
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 36500 -subj "/CN=Caju Test Root" \
  -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign" -out ca.pem
mk() {   # name, genpkey args
  openssl genpkey $2 -out $1.key 2>/dev/null
  openssl req -new -key $1.key -subj "/CN=localhost" -out $1.csr
  printf 'basicConstraints=CA:FALSE\nkeyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=DNS:localhost,IP:127.0.0.1\n' > ext.cnf
  openssl x509 -req -in $1.csr -CA ca.pem -CAkey ca.key -CAcreateserial -days 36500 -sha256 -extfile ext.cnf -out $1.pem 2>/dev/null
  rm -f $1.csr ext.cnf
}
mk ecdsa "-algorithm EC -pkeyopt ec_paramgen_curve:P-256"
mk rsa "-algorithm RSA -pkeyopt rsa_keygen_bits:2048"
mk ed25519 "-algorithm ed25519"
rm -f ca.srl ca.key
