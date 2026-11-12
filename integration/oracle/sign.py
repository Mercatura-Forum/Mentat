#!/usr/bin/env python3
"""The signing flow, re-derived from the log by code that shares nothing with the contract.

WHAT THIS CHECKS. Every block of the signing battery's log is decoded with the enterprise reader's
own envelope (every hash and link verified) and folded here by rules written from the design: a
request is addressed once; a person acts at their turn; a challenge is the one the contract's own
counter would have issued; an assertion is a WebAuthn ES256 assertion whose client data names that
challenge and the contract's origin, whose authenticator data names the relying party with the
user present and verified, and whose signature verifies under the signer's registered P-256 key - 
verified here with `cryptography`, an implementation this tree did not write; the last signer's
signature completes the request and its seal is recomputed from the content's fingerprint and the
signatures in order, and must be the one the contract printed. A block the rules would refuse is
a fault, because the log holds only what the contract accepted.

Usage: sign.py <signing battery log>

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import base64
import hashlib
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from cryptography.exceptions import InvalidSignature                 # noqa: E402
from cryptography.hazmat.primitives import hashes, serialization       # noqa: E402
from cryptography.hazmat.primitives.asymmetric import ec               # noqa: E402

import log_reader                                                    # noqa: E402
from canonical import hash_with_domain                               # noqa: E402

# The contract's signing context, as `EvFold.SIGNING_CTX` declares it, and the seal's domain.
CONTRACT = "qorza"
ORIGIN = "https://qorza.app"
DOMAIN = "QORZA-SIGN-v1"
RP_ID = "qorza.app"
SEAL_DOMAIN = "MENTAT-SIGN-SEAL-v1"
PRINCIPAL_FIELD = 30


def b64url(b: bytes) -> str:
    return base64.urlsafe_b64encode(b).decode("ascii").rstrip("=")


def unb64(t: str) -> bytes:
    return base64.urlsafe_b64decode(t + "=" * (-len(t) % 4))


def nonce_for(counter: int) -> str:
    return hash_with_domain("THEBES-SIGN-NONCE-v1", f"{CONTRACT}|{counter}".encode()).hex()


def challenge_for(target: str, target_hash: str, nonce: str) -> bytes:
    return hash_with_domain(DOMAIN, f"{CONTRACT}|{target}|{target_hash}|{nonce}".encode())


def principal_field(p: bytes) -> bytes:
    return bytes([len(p)]) + p + bytes(PRINCIPAL_FIELD - 1 - len(p))


class Flow:
    def __init__(self):
        self.keys = {}          # (owner, credentialId) -> spki bytes
        self.documents = {}     # id -> plainHash
        self.requests = {}      # id -> dict
        self.counter = 0
        self.pending = {}       # nonce -> (owner, requestId, challenge)
        self.seals = {}         # requestId -> seal hex
        self.verified = 0
        self.faults = []

    def fault(self, block, what):
        self.faults.append("block %d: %s" % (block["index"], what))

    def apply(self, block):
        c = block["command"]
        name = c["family"]
        caller = block["caller"]
        if name == "registerSigningKey":
            if c["scheme"] == "es256":
                self.keys[(caller, c["credentialId"])] = unb64(c["publicKey"])
        elif name == "registerDocument":
            self.documents[len(self.documents) + 1] = c["facts"]["plainHash"]
        elif name == "createSignatureRequest":
            f = c["facts"]
            rid = len(self.requests) + 1
            self.requests[rid] = {"documentId": f["documentId"], "hash": self.documents[f["documentId"]],
                                  "deadline": f["deadlineDay"], "signers": [], "signed": [], "state": "open"}
        elif name == "nameSigners":
            r = self.requests[c["requestId"]]
            if r["signers"]:
                return self.fault(block, "a request addressed twice")
            if len(set(c["signers"])) != len(c["signers"]) or not c["signers"]:
                return self.fault(block, "an order with nobody or somebody twice")
            r["signers"] = list(c["signers"])
        elif name == "beginSignature":
            r = self.requests[c["requestId"]]
            if not self.at_turn(r, caller, block):
                return
            self.counter += 1
            nonce = nonce_for(self.counter)
            self.pending[nonce] = (caller, c["requestId"], challenge_for("signature-request:%d" % c["requestId"], r["hash"], nonce))
        elif name == "completeSignature":
            f = c["facts"]
            r = self.requests[f["requestId"]]
            if not self.at_turn(r, caller, block):
                return
            p = self.pending.get(f["nonce"])
            if p is None or p[0] != caller or p[1] != f["requestId"]:
                return self.fault(block, "a signature over a challenge this reader never saw the contract issue")
            sig = unb64(f["signatureB64"])
            if not self.verify(block, caller, f, p[2], sig):
                return
            del self.pending[f["nonce"]]
            self.verified += 1
            r["signed"].append((caller, sig))
            if len(r["signed"]) == len(r["signers"]):
                r["state"] = "completed"
                self.seals[f["requestId"]] = self.seal_of(r)
        elif name == "declineSignature":
            r = self.requests[c["requestId"]]
            if not self.at_turn(r, caller, block):
                return
            r["state"] = "declined"
        elif name == "expireSignatureRequest":
            r = self.requests[c["requestId"]]
            if r["state"] != "open" or block["day"] <= r["deadline"]:
                return self.fault(block, "a request expired that was not open past its deadline")
            r["state"] = "expired"

    def at_turn(self, r, caller, block):
        if r["state"] != "open":
            self.fault(block, "an act on a request that is not open")
            return False
        if block["day"] > r["deadline"]:
            self.fault(block, "an act on a request past its deadline")
            return False
        if not r["signers"]:
            self.fault(block, "an act on a request addressed to nobody")
            return False
        expected = r["signers"][len(r["signed"])]
        if expected != caller:
            self.fault(block, "an act out of turn")
            return False
        return True

    def verify(self, block, caller, f, challenge, sig):
        spki = self.keys.get((caller, f["credentialId"]))
        if spki is None:
            self.fault(block, "a signature under a passkey nobody registered")
            return False
        client = unb64(f["clientDataB64"])
        auth = unb64(f["authDataB64"])
        try:
            cj = json.loads(client)
        except ValueError:
            self.fault(block, "client data that is not JSON")
            return False
        if cj.get("type") != "webauthn.get" or cj.get("challenge") != b64url(challenge) or cj.get("origin") != ORIGIN or cj.get("crossOrigin"):
            self.fault(block, "client data that does not name this challenge and origin")
            return False
        if len(auth) < 37 or auth[:32] != hashlib.sha256(RP_ID.encode()).digest() or (auth[32] & 0x05) != 0x05:
            self.fault(block, "authenticator data that does not name the relying party with the user present and verified")
            return False
        key = serialization.load_der_public_key(spki)
        try:
            key.verify(sig, auth + hashlib.sha256(client).digest(), ec.ECDSA(hashes.SHA256()))
        except InvalidSignature:
            self.fault(block, "a signature that does not verify under the registered key")
            return False
        return True

    def seal_of(self, r):
        payload = bytes.fromhex(r["hash"]) + bytes([len(r["signers"])])
        for (signer, sig) in r["signed"]:
            payload += principal_field(signer) + hashlib.sha256(sig).digest()
        return hash_with_domain(SEAL_DOMAIN, payload).hex()


def main():
    if len(sys.argv) < 2:
        print("usage: sign.py <signing battery log>")
        return 2
    pieces, tip, printed = {}, None, {}
    for line in open(sys.argv[1], encoding="utf-8"):
        line = line.strip()
        if line.startswith("block: "):
            _, idx, part, hexed = line.split(None, 3)
            pieces.setdefault(int(idx), {})[int(part)] = hexed
        elif line.startswith("tip: "):
            tip = bytes.fromhex(line.split(None, 1)[1])
        elif line.startswith("seal: "):
            _, rid, content, seal = line.split()
            printed[int(rid)] = (content, seal)
    blocks = []
    for idx, parts in sorted(pieces.items()):
        if sorted(parts) != list(range(len(parts))):
            print("ORACLE STOPPED: block %d is missing one of its parts" % idx)
            return 1
        blocks.append(bytes.fromhex("".join(parts[i] for i in range(len(parts)))))
    if not blocks:
        print("ORACLE STOPPED: the battery printed no blocks")
        return 1

    flow = Flow()
    prev = None
    faults = []
    for i, raw in enumerate(blocks):
        try:
            b = log_reader.decode_block(i, raw)
            if b["index"] != i or b["parent"] != prev:
                faults.append("block %d does not link to the block below it" % i)
                break
            prev = b["hash"]
            flow.apply(b)
        except (ValueError, KeyError) as e:
            faults.append("block %d: %s" % (i, e))
            break
    if tip is not None and prev != tip:
        faults.append("the last block's hash is not the tip the contract published")
    faults.extend(flow.faults)
    fails = 0

    def report(name, ok, detail):
        nonlocal fails
        fails += 0 if ok else 1
        print("%s %s: %s" % ("PASS" if ok else "FAIL", name, detail))

    report("S1", not faults, "%d block(s) read, every hash and link verified, and folded by the signing rules" % len(blocks)
           if not faults else "; ".join(faults[:3]))
    report("S2", flow.verified > 0, "%d ES256 assertion(s) verified with cryptography's P-256 over the challenge this reader recomputed" % flow.verified)
    agreed = sum(1 for rid, seal in flow.seals.items() if printed.get(rid, ("", ""))[1] == seal
                 and printed[rid][0] == flow.requests[rid]["hash"])
    report("S3", flow.seals and agreed == len(flow.seals) == len(printed),
           "%d seal(s) recomputed from the content and the signatures in order agree with the contract's" % agreed
           if agreed == len(flow.seals) == len(printed) else "seals: reader %r, contract %r" % (flow.seals, printed))
    states = {}
    for r in flow.requests.values():
        states[r["state"]] = states.get(r["state"], 0) + 1
    report("S4", states.get("completed") == 2 and states.get("declined") == 1 and states.get("expired") == 1,
           "requests by state from the log: %r" % states)
    # and the verifier is connected: the first assertion with one byte of signature changed is refused
    sample = next((b for b in (log_reader.decode_block(i, raw) for i, raw in enumerate(blocks)) if b["command"]["family"] == "completeSignature"), None)
    connected = False
    if sample is not None:
        f = sample["command"]["facts"]
        r = flow.requests[f["requestId"]]
        sig = bytearray(unb64(f["signatureB64"]))
        sig[-1] ^= 0x01
        probe = Flow()
        probe.keys = flow.keys
        challenge = challenge_for("signature-request:%d" % f["requestId"], r["hash"], f["nonce"])
        connected = not probe.verify(sample, sample["caller"], f, challenge, bytes(sig)) and probe.faults
    report("S5", bool(connected), "the same assertion with one byte of signature changed is refused by this reader's verifier")
    print("count: blocks folded = %d" % len(blocks))
    print("count: assertions verified independently = %d" % flow.verified)
    print("count: seals recomputed and agreed = %d" % agreed)
    print("count: signing checks run = 5")
    if fails:
        print("SIGN ORACLE FAILED: %d check(s) red" % fails)
        return 1
    print("SIGN ORACLE GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
