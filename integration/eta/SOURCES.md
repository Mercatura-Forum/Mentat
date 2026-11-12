# The authority's published example

Three files from the Egyptian Tax Authority's SDK portal, read 2026-09-20 (each HTTP 200):

| File | Source | SHA-256 |
|---|---|---|
| `authority-example.json` | https://sdk.invoicing.eta.gov.eg/files/one-doc.json | 586615e7f278791e774e946c0b20b19c4eba13098527eea9234c298adfed087e |
| `authority-example-serialized.txt` | https://sdk.invoicing.eta.gov.eg/files/one-doc-serialized.json.txt | d43fae25b02b7e466fa5aa39e5fa45c7d92661e5b0a0e7964e04783bff3c2651 |
| `authority-example-signed.json` | https://sdk.invoicing.eta.gov.eg/files/one-doc-I.json | 4443867eb420ab3374f7678d13b781a0c801033307f7dcd69442230fe05fe254 |

They are the authority's own statement of what a document, its canonical serialisation and its
seal look like, carried here so the gate can hold this system's serialisation and seal verifier to
them. The SHA-256 of the serialised example is the `messageDigest` inside the seal the signed
example carries, which is what makes the three files one vector.

Attribution: Thebes Core Team.
