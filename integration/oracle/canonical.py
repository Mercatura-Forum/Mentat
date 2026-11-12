"""The canonical codec, written independently in Python.

This is deliberately NOT a translation of the Motoko. It is written from the format as documented,
so that agreement between the two is evidence and not a shared bug. Every byte layout below is
stated in a comment before it is implemented, and the contract's own battery is what proves the two
agree.

  nat        one length byte n, then n big-endian bytes. Zero is the single byte 0x00.
  nat64      eight big-endian bytes, always.
  nat8/byte  one byte.
  bool       0x00 or 0x01.
  len16      two big-endian bytes.
  text       len16 of the UTF-8 length, then the UTF-8 bytes.
  blob       len16 of the length, then the bytes.
  principal  one length byte, then that many bytes (at most 29).
  opt X      0x00 for none; 0x01 followed by X.

  hashWithDomain(domain, payload) = SHA-256( text(domain) || payload )

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""

import hashlib

MAX_PRINCIPAL_BYTES = 29


class Reader:
    def __init__(self, data: bytes):
        self.data = data
        self.pos = 0

    def remaining(self) -> int:
        return len(self.data) - self.pos

    def at_end(self) -> bool:
        return self.pos >= len(self.data)

    def take(self, n: int) -> bytes:
        if self.pos + n > len(self.data):
            raise ValueError("read past the end: wanted %d, have %d" % (n, self.remaining()))
        out = self.data[self.pos:self.pos + n]
        self.pos += n
        return out

    def byte(self) -> int:
        return self.take(1)[0]

    def nat(self) -> int:
        n = self.byte()
        if n == 0:
            return 0
        return int.from_bytes(self.take(n), "big")

    def nat64(self) -> int:
        return int.from_bytes(self.take(8), "big")

    def nat8(self) -> int:
        return self.byte()

    def bool(self) -> bool:
        b = self.byte()
        if b not in (0, 1):
            raise ValueError("a bool that is neither 0 nor 1: %d" % b)
        return b == 1

    def len16(self) -> int:
        return int.from_bytes(self.take(2), "big")

    def text(self) -> str:
        return self.take(self.len16()).decode("utf-8")

    def blob(self) -> bytes:
        return self.take(self.len16())

    def principal(self) -> bytes:
        n = self.byte()
        if n > MAX_PRINCIPAL_BYTES:
            raise ValueError("a principal of %d bytes" % n)
        return self.take(n)

    def opt_blob(self):
        tag = self.byte()
        if tag == 0:
            return None
        if tag != 1:
            raise ValueError("an option tag that is neither 0 nor 1: %d" % tag)
        return self.blob()

    def opt_nat(self):
        tag = self.byte()
        if tag == 0:
            return None
        if tag != 1:
            raise ValueError("an option tag that is neither 0 nor 1: %d" % tag)
        return self.nat()


def write_nat(n: int) -> bytes:
    if n == 0:
        return b"\x00"
    count = (n.bit_length() + 7) // 8
    if count > 255:
        raise ValueError("a nat of %d bytes" % count)
    return bytes([count]) + n.to_bytes(count, "big")


def write_text(t: str) -> bytes:
    b = t.encode("utf-8")
    if len(b) > 65535:
        raise ValueError("a text of %d bytes" % len(b))
    return len(b).to_bytes(2, "big") + b


def hash_with_domain(domain: str, payload: bytes) -> bytes:
    return hashlib.sha256(write_text(domain) + payload).digest()
