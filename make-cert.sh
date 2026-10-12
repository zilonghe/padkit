#!/bin/sh
# Create a local self-signed code-signing identity so macOS keeps PadKit's Accessibility permission across rebuilds.
set -e
if security find-identity -p codesigning | grep -q "PadKit Local Signing"; then echo "Already exists"; exit 0; fi
D=$(mktemp -d)
cat > "$D/c.cnf" <<'CNF'
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=PadKit Local Signing
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
openssl req -x509 -newkey rsa:2048 -nodes -keyout "$D/k.pem" -out "$D/c.pem" -days 3650 -config "$D/c.cnf"
openssl pkcs12 -export -legacy -inkey "$D/k.pem" -in "$D/c.pem" -out "$D/p.p12" -passout pass:padkit 2>/dev/null || openssl pkcs12 -export -inkey "$D/k.pem" -in "$D/c.pem" -out "$D/p.p12" -passout pass:padkit
security import "$D/p.p12" -k ~/Library/Keychains/login.keychain-db -P padkit -T /usr/bin/codesign
rm -rf "$D"
echo "Created 'PadKit Local Signing'"
