#!/usr/bin/env python3
"""The largest function in the contract's module, held under a bound.

The engine a node runs compiles a module function by function, and what it holds while compiling one
grows faster than the function does. The command decoder was once a single function of 642 KB - one
switch over every command, its fields read inline - and compiling the module took 5 GB at once: past
the memory a node may hold, so the chain shed every submission after the deploy. Split into one
function per run of tags, the same module compiled in 440 MB. This check keeps the next extension from
growing a function back past the bound, which no battery would notice: a battery runs the module, it
does not watch what compiling it costs.

It reads the module's own sections and nothing else - the code section for each body's size, the name
section for what to call it - so it needs no tool the gate does not already have. Before it reads the
contract it reads a module it builds itself, one function a byte past the bound, and must refuse it:
a bound that a module over it passes is not a bound.

Usage: wasm_bound.py <module.wasm> [bound-in-bytes]
Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import sys

BOUND = 128 * 1024


def leb(b, i):
    r = s = 0
    while True:
        x = b[i]; i += 1
        r |= (x & 0x7F) << s; s += 7
        if x < 0x80:
            return r, i


def uleb(n):
    out = bytearray()
    while True:
        x = n & 0x7F; n >>= 7
        out.append(x | (0x80 if n else 0))
        if not n:
            return bytes(out)


def sections(b):
    if b[:4] != b"\0asm":
        raise ValueError("not a wasm module")
    i, out = 8, []
    while i < len(b):
        sid = b[i]; i += 1
        n, i = leb(b, i)
        out.append((sid, i, n)); i += n
    return out


def imported_functions(b, secs):
    count = 0
    for sid, st, _n in secs:
        if sid != 2:
            continue
        j = st
        k, j = leb(b, j)
        for _ in range(k):
            for _field in range(2):
                ln, j = leb(b, j); j += ln
            kind = b[j]; j += 1
            if kind == 0:
                _, j = leb(b, j); count += 1
            elif kind == 1:
                j += 1; flags = b[j]; j += 1; _, j = leb(b, j)
                if flags & 1:
                    _, j = leb(b, j)
            elif kind == 2:
                flags = b[j]; j += 1; _, j = leb(b, j)
                if flags & 1:
                    _, j = leb(b, j)
            elif kind == 3:
                j += 2
            else:
                raise ValueError("an import of kind %d" % kind)
    return count


def function_names(b, secs):
    names = {}
    for sid, st, n in secs:
        if sid != 0:
            continue
        j = st
        ln, j = leb(b, j)
        if b[j:j + ln] != b"name":
            continue
        j += ln
        end = st + n
        while j < end:
            sub = b[j]; j += 1
            size, j = leb(b, j)
            nxt = j + size
            if sub == 1:
                k, j = leb(b, j)
                for _ in range(k):
                    idx, j = leb(b, j)
                    ln, j = leb(b, j)
                    names[idx] = b[j:j + ln].decode("utf-8", "replace"); j += ln
            j = nxt
    return names


def largest(b):
    """(size, name) of every function body, largest first."""
    secs = sections(b)
    base = imported_functions(b, secs)
    names = function_names(b, secs)
    bodies = []
    for sid, st, _n in secs:
        if sid != 10:
            continue
        j = st
        k, j = leb(b, j)
        for idx in range(k):
            size, j = leb(b, j)
            bodies.append((size, names.get(base + idx, "function %d" % (base + idx))))
            j += size
    if not bodies:
        raise ValueError("a module with no code section")
    return sorted(bodies, reverse=True)


def module_with_one_body(size):
    """A module of one function `() -> ()` whose body is exactly `size` bytes: no locals, nops, end."""
    assert size >= 2
    body = b"\x00" + b"\x01" * (size - 2) + b"\x0b"
    typesec = b"\x01\x60\x00\x00"
    funcsec = b"\x01\x00"
    codesec = b"\x01" + uleb(len(body)) + body
    def sec(i, payload):
        return bytes([i]) + uleb(len(payload)) + payload
    return b"\0asm\x01\0\0\0" + sec(1, typesec) + sec(3, funcsec) + sec(10, codesec)


def main():
    if len(sys.argv) < 2:
        print(__doc__.strip().splitlines()[-2]); return 2
    bound = int(sys.argv[2]) if len(sys.argv) > 2 else BOUND
    # THE CONTROL: a module one byte past the bound must be refused, one at the bound must not
    over = largest(module_with_one_body(bound + 1))[0][0]
    at = largest(module_with_one_body(bound))[0][0]
    if not (over > bound and at <= bound):
        print("CONTROL BROKEN: the bound check read a body of %d as %d and one of %d as %d" % (bound + 1, over, bound, at))
        return 1
    b = open(sys.argv[1], "rb").read()
    bodies = largest(b)
    print("count: functions in the module = %d" % len(bodies))
    print("the largest function: %s, %d bytes, against a bound of %d" % (bodies[0][1], bodies[0][0], bound))
    over = [(s, n) for s, n in bodies if s > bound]
    if over:
        for s, n in over[:10]:
            print("OVER THE BOUND: %s, %d bytes" % (n, s))
        print("WASM BOUND FAILED: %d function(s) past %d bytes - split them as Encoding.mo splits readV1" % (len(over), bound))
        return 1
    print("WASM BOUND GREEN")
    return 0


if __name__ == "__main__":
    sys.exit(main())
