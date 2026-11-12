#!/usr/bin/env python3
"""The tax authority's document, re-derived: the serialisation, its digest, and the seal.

The Egyptian Tax Authority's SDK states how a document is serialised before it is sealed (its
"Document Serialization Approach" page) and publishes one signed example. This is that
serialisation written a second time, in Python, from the page - not from the contract's code - 
and it is held to the authority's example first: `self_test` serialises the published example and
requires the SHA-256 to be the `messageDigest` inside the authority's own seal. Only a twin that
passes that is allowed to judge the contract.

What it then judges, from a battery's log:

  * every `eta-submission:` line - the submission body the contract built - is parsed with the
    numbers kept as their text, the document's `signatures` are set aside, the rest is serialised
    by this twin and hashed, and the hash must be the `eta-digest:` the contract recorded for it;
  * the seal in that body is handed to OpenSSL (`openssl cms -verify`) together with the canonical
    bytes this twin produced and the anchor certificate the battery names, and OpenSSL must accept
    it - an independent verifier that shares nothing with the kernel's;
  * and the same body with one character of its canonical form changed must be refused by
    OpenSSL, so the verifier is shown to be connected.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import base64
import hashlib
import json
import subprocess
import sys
import tempfile
from collections import OrderedDict
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUTHORITY_SAMPLE = HERE.parent / "eta" / "authority-example-signed.json"
# The SHA-256 of the authority example's canonical serialisation, which is the messageDigest in
# its seal (read off the seal with `openssl cms -cmsout -print`).
AUTHORITY_DIGEST = "d43fae25b02b7e466fa5aa39e5fa45c7d92661e5b0a0e7964e04783bff3c2651"


def load_raw(text):
    """JSON with numbers kept as their text: the authority takes a value 'just like it is in the
    input document', so 0.0 must stay 0.0 and 10.00 must stay 10.00."""
    return json.loads(text, object_pairs_hook=OrderedDict, parse_float=lambda s: s,
                      parse_int=lambda s: s)


def serialize(v):
    """The authority's algorithm: names upper-cased and quoted, values quoted as they are, an
    array prefixed by its name and each element preceded by the name again."""
    if isinstance(v, bool):
        return '"' + ("true" if v else "false") + '"'
    if v is None:
        return '""'
    if not isinstance(v, (dict, list)):
        return '"' + str(v) + '"'
    out = ""
    for k, val in v.items():
        name = '"' + k.upper() + '"'
        if isinstance(val, list):
            out += name
            for e in val:
                out += name + serialize(e)
        else:
            out += name + serialize(val)
    return out


def canonical_of(document):
    """The document without its signatures, serialised."""
    unsigned = OrderedDict((k, v) for k, v in document.items() if k != "signatures")
    return serialize(unsigned)


def digest_hex(canonical):
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


def self_test():
    """The twin against the authority's own example. A twin that cannot reproduce the authority's
    digest has no business judging anything."""
    text = AUTHORITY_SAMPLE.read_text(encoding="utf-8-sig")
    d = load_raw(text)
    doc = d["documents"][0] if isinstance(d, dict) and "documents" in d else d
    canonical = canonical_of(doc)
    got = digest_hex(canonical)
    return got == AUTHORITY_DIGEST, got, len(canonical)


def reassemble(log, tag):
    """The battery prints a long value as `<tag>-part:` lines closed by `<tag>-end:`, because the
    runtime truncates a long line; this puts each value back together."""
    out, acc = [], None
    for line in log.splitlines():
        if line.startswith(tag + "-part: "):
            acc = (acc or "") + line[len(tag) + 7:]
        elif line.startswith(tag + "-end:"):
            out.append(acc or "")
            acc = None
    return out


def openssl_verify(seal_der, canonical_bytes, anchor_pem):
    """OpenSSL's verdict on the seal over these bytes under this anchor."""
    with tempfile.TemporaryDirectory() as td:
        seal = Path(td) / "seal.der"
        content = Path(td) / "content.bin"
        seal.write_bytes(seal_der)
        content.write_bytes(canonical_bytes)
        cmd = ["openssl", "cms", "-verify", "-binary", "-inform", "DER", "-in", str(seal),
               "-content", str(content), "-CAfile", str(anchor_pem), "-purpose", "any", "-out", "/dev/null"]
        p = subprocess.run(cmd, capture_output=True, text=True)
        return p.returncode == 0, (p.stderr or p.stdout).strip()[-200:]


def main():
    if len(sys.argv) < 3:
        print("usage: eta.py <battery log> <anchor certificate PEM>")
        return 2
    log = Path(sys.argv[1]).read_text()
    anchor = Path(sys.argv[2])
    fails = 0

    ok, got, n = self_test()
    print("%s the twin reproduces the authority's digest over its published example (%d characters): %s…"
          % ("PASS" if ok else "FAIL", n, got[:16]))
    if not ok:
        print("ORACLE STOPPED: the serialisation twin does not reproduce the authority's own example")
        return 1

    bodies = reassemble(log, "eta-submission")
    digests = [l.split(":", 1)[1].strip() for l in log.splitlines() if l.startswith("eta-digest:")]
    if not bodies or len(bodies) != len(digests):
        print("ORACLE STOPPED: %d submission bodies and %d digests in the log" % (len(bodies), len(digests)))
        return 1

    verified = 0
    refused = 0
    for i, (body, want) in enumerate(zip(bodies, digests)):
        env = load_raw(body)
        doc = env["documents"][0]
        canonical = canonical_of(doc)
        got = digest_hex(canonical)
        agree = got == want
        print("%s document %d: the twin's digest %s the contract's (%s…)" % ("PASS" if agree else "FAIL", i + 1, "is" if agree else "IS NOT", got[:16]))
        if not agree:
            fails += 1
            continue
        seal = base64.b64decode(doc["signatures"][0]["value"])
        ok, why = openssl_verify(seal, canonical.encode("utf-8"), anchor)
        print("%s document %d: OpenSSL %s the seal under the anchor%s" % ("PASS" if ok else "FAIL", i + 1, "accepts" if ok else "REFUSES", "" if ok else ": " + why))
        if not ok:
            fails += 1
            continue
        verified += 1
        # THE CONTROL: one character of the canonical form changed, and OpenSSL must refuse.
        perturbed = canonical[:-1] + ("0" if canonical[-1] != "0" else "1")
        ok2, _ = openssl_verify(seal, perturbed.encode("utf-8"), anchor)
        print("%s document %d: OpenSSL refuses the seal over a document changed by one character" % ("PASS" if not ok2 else "FAIL", i + 1))
        if ok2:
            fails += 1
        else:
            refused += 1

    print("count: documents whose digest the twin re-derived = %d" % verified)
    print("count: seals OpenSSL accepted = %d" % verified)
    print("count: perturbed documents OpenSSL refused = %d" % refused)
    if fails:
        print("ETA ORACLE FAILED: %d check(s) red" % fails)
        return 1
    print("ETA ORACLE GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
