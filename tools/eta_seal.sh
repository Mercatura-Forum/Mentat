#!/usr/bin/env bash
# THE SEALING TOKEN, PLAYED BY OPENSSL: the seals `test/Eta.test.mo` embeds, made outside the contract.
#
# A filing's seal is a CAdES-BES made by the taxpayer's certificate holder over the SHA-256 of the
# document's canonical serialisation. In a company's own deployment that is a certification authority's token; in
# the battery it is this script, with keys made for the purpose under `test/fixtures/eta/`: a root
# (the anchor the company configures), a leaf issued by it that carries the taxpayer identifier
# the battery's company files under, a leaf for ANOTHER taxpayer, a self-signed leaf with the right
# identifier that is NOT issued by the root, and a leaf whose validity ended in 2020. The seals are
# made with `openssl cms -sign -cades -econtent_type 1.2.840.113549.1.7.5`, the exact shape the
# authority's own published example has (its content type is digestedData).
#
# THE CERTIFICATES ARE VALID FROM 2026-01-01 TO 2036-01-01 (the lapsed one, 2020 only), so the
# battery's business day, 2026-09-13, falls inside them whatever day the fixtures were made.
#
# THE TWO PASSES. The seal is over the canonical bytes of the very document the battery derives, and
# the battery cannot run without the vector module it imports. So this writes the module twice:
# first with seals over a bootstrap string (well-formed seals that cannot match any document),
# runs the battery - which prints `eta-canonical:` for each document it prepares and goes red at
# its seal step - then seals THOSE canonical bytes and writes the module again, after which the
# battery is green. The committed module is the second pass's. When the document changes, the
# battery goes red at "the vector's digest is the document's" and this script is run again.
#
#   tools/eta_seal.sh            regenerate test/EtaVectors.mo (keys are made once and kept)
#
# Attribution: Thebes Core Team. Licence: Apache 2.0.
set -euo pipefail
HERE="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
cd "$HERE"
FX=test/fixtures/eta
mkdir -p "$FX"

TAXID="EG-999-888-777"      # the identifier test/Eta.test.mo's company files under

mkcert() {   # mkcert <name> <subject> <days> [<extra x509 -req args>]
  local name="$1" subject="$2" days="$3"; shift 3
  [ -f "$FX/$name-key.pem" ] || openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$FX/$name-key.pem" 2>/dev/null
  printf '[req]\ndistinguished_name=dn\nprompt=no\n[dn]\n%s\n' "$subject" > "$FX/$name.cnf"
  openssl req -new -key "$FX/$name-key.pem" -out "$FX/$name.csr" -config "$FX/$name.cnf" 2>/dev/null
  printf 'basicConstraints=CA:FALSE\nkeyUsage=digitalSignature,nonRepudiation\nsubjectKeyIdentifier=hash\nauthorityKeyIdentifier=keyid\n' > "$FX/leaf.ext"
  openssl x509 -req -in "$FX/$name.csr" -CA "$FX/root-cert.pem" -CAkey "$FX/root-key.pem" -CAcreateserial \
    -out "$FX/$name-cert.pem" -days "$days" -sha256 -extfile "$FX/leaf.ext" "$@" 2>/dev/null
  openssl x509 -in "$FX/$name-cert.pem" -outform DER -out "$FX/$name-cert.der"
  rm -f "$FX/$name.csr" "$FX/$name.cnf" "$FX/leaf.ext" "$FX/root-cert.srl"
}

if [ ! -f "$FX/root-cert.pem" ]; then
  openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$FX/root-key.pem" 2>/dev/null
  printf '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nC=EG\nO=Test Sealing Authority\nCN=Test Sealing Root\n[ext]\nbasicConstraints=critical,CA:TRUE\nkeyUsage=keyCertSign,cRLSign\nsubjectKeyIdentifier=hash\n' > "$FX/root.cnf"
  openssl req -new -x509 -key "$FX/root-key.pem" -out "$FX/root-cert.pem" -not_before 20260101000000Z -not_after 20360101000000Z -config "$FX/root.cnf" -sha256
  rm -f "$FX/root.cnf"
fi
openssl x509 -in "$FX/root-cert.pem" -outform DER -out "$FX/root-cert.der"
[ -f "$FX/seal-cert.pem" ]    || mkcert seal    "C=EG
O=Test Seal Holder
organizationIdentifier=VATEG-$TAXID
CN=Test Sealing Unit" 3650 -not_before 20260101000000Z -not_after 20360101000000Z
[ -f "$FX/other-cert.pem" ]   || mkcert other   "C=EG
O=Another Taxpayer
organizationIdentifier=VATEG-EG-111-222-333
CN=Another Sealing Unit" 3650 -not_before 20260101000000Z -not_after 20360101000000Z
[ -f "$FX/expired-cert.pem" ] || mkcert expired "C=EG
O=Test Seal Holder
organizationIdentifier=VATEG-$TAXID
CN=A Lapsed Sealing Unit" 1 -not_before 20200101000000Z -not_after 20201231235959Z
if [ ! -f "$FX/loose-cert.pem" ]; then
  # self-signed, right identifier, not issued by the root
  [ -f "$FX/loose-key.pem" ] || openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$FX/loose-key.pem" 2>/dev/null
  printf '[req]\ndistinguished_name=dn\nprompt=no\nx509_extensions=ext\n[dn]\nC=EG\nO=Test Seal Holder\norganizationIdentifier=VATEG-%s\nCN=An Unanchored Sealing Unit\n[ext]\nbasicConstraints=CA:FALSE\nkeyUsage=digitalSignature\nsubjectKeyIdentifier=hash\n' "$TAXID" > "$FX/loose.cnf"
  openssl req -new -x509 -key "$FX/loose-key.pem" -out "$FX/loose-cert.pem" -not_before 20260101000000Z -not_after 20360101000000Z -config "$FX/loose.cnf" -sha256
  rm -f "$FX/loose.cnf"
fi

seal() {   # seal <name> <content file> > der
  local name="$1" content="$2"
  openssl cms -sign -binary -in "$content" -signer "$FX/$name-cert.pem" -inkey "$FX/$name-key.pem" \
    -md sha256 -cades -nosmimecap -econtent_type 1.2.840.113549.1.7.5 -outform DER
}

write_module() {   # write_module <invoice canonical file> <credit canonical file>
  local inv="$1" cn="$2"
  python3 - "$FX" "$inv" "$cn" > test/EtaVectors.mo <<'EOF'
import hashlib, subprocess, sys
from pathlib import Path
fx, inv, cn = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
def lit(b): return '"' + "".join("\\%02x" % x for x in b) + '"'
def seal(name, content):
    return subprocess.run(["openssl", "cms", "-sign", "-binary", "-in", str(content), "-signer", str(fx / f"{name}-cert.pem"),
                           "-inkey", str(fx / f"{name}-key.pem"), "-md", "sha256", "-cades", "-nosmimecap",
                           "-econtent_type", "1.2.840.113549.1.7.5", "-outform", "DER"], check=True, capture_output=True).stdout
print("/// EtaVectors.mo - generated by tools/eta_seal.sh; do not edit. The seals test/Eta.test.mo embeds,")
print("/// made by OpenSSL playing the sealing token over the canonical bytes the battery derives.")
print("///")
print("/// Attribution: Thebes Core Team. Licence: Apache 2.0.")
print("module {")
print("  /// The anchor: the test root the company configures. Every seal must chain to it.")
print("  public let ANCHOR_DER : Blob = %s;" % lit((fx / "root-cert.der").read_bytes()))
print("  /// The sealing certificate, issued by the root, carrying the taxpayer identifier the company files under.")
print("  public let SEAL_CERT_DER : Blob = %s;" % lit((fx / "seal-cert.der").read_bytes()))
for label, f in (("INVOICE", inv), ("CREDIT", cn)):
    b = f.read_bytes()
    print("  /// SHA-256 of the %s document's canonical bytes as sealed (%d bytes)." % (label.lower(), len(b)))
    print("  public let %s_DIGEST : Blob = %s;" % (label, lit(hashlib.sha256(b).digest())))
    print("  public let %s_SEAL : Blob = %s;" % (label, lit(seal("seal", f))))
# the invoice's seal and digest, also written as files for a client that submits them
(fx / "invoice-seal.der").write_bytes(seal("seal", inv))
(fx / "invoice-digest.hex").write_text(hashlib.sha256(inv.read_bytes()).hexdigest() + "\n")
print("  /// The invoice sealed by ANOTHER taxpayer's certificate, issued by the same root.")
print("  public let OTHER_COMPANY_SEAL : Blob = %s;" % lit(seal("other", inv)))
print("  /// The invoice sealed by a self-signed certificate with the right identifier, not issued by the root.")
print("  public let UNANCHORED_SEAL : Blob = %s;" % lit(seal("loose", inv)))
print("  /// The invoice sealed by a certificate whose validity ended in 2020.")
print("  public let EXPIRED_SEAL : Blob = %s;" % lit(seal("expired", inv)))
print("}")
EOF
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
printf 'bootstrap' > "$TMP/inv.txt"; printf 'bootstrap-credit' > "$TMP/cn.txt"
write_module "$TMP/inv.txt" "$TMP/cn.txt"
echo "pass 1: bootstrap vectors written; running the battery to learn the canonical bytes"
TEST_OUT="$TMP/out" ./test/run.sh Eta > "$TMP/pass1.log" 2>&1 || true
# the canonical bytes are printed in parts (the runtime truncates a long line); reassemble each
awk '/^eta-canonical-part: /{ sub(/^eta-canonical-part: /, ""); acc = acc $0 } /^eta-canonical-end:/{ print acc; acc = "" }' "$TMP/out/Eta.log" > "$TMP/canon.txt"
n=$(grep -c '' "$TMP/canon.txt")
[ "$n" -ge 2 ] || { echo "eta_seal: expected two canonical documents, found $n"; tail -20 "$TMP/pass1.log"; exit 1; }
sed -n '1p' "$TMP/canon.txt" | xxd -r -p > "$TMP/inv.bin"
sed -n '2p' "$TMP/canon.txt" | xxd -r -p > "$TMP/cn.bin"
write_module "$TMP/inv.bin" "$TMP/cn.bin"
echo "pass 2: seals over $(stat -c%s "$TMP/inv.bin") and $(stat -c%s "$TMP/cn.bin") canonical bytes written to test/EtaVectors.mo"
TEST_OUT="$TMP/out2" ./test/run.sh Eta 2>&1 | tail -3
