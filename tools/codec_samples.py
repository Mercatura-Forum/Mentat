#!/usr/bin/env python3
"""Writes test/CodecSamples.mo and test/fixtures/codec_samples.json: two commands of every family in `Cmd.FAMILIES`,
built from the command's own type, and the value each must read back as.

THE PLAIN SAMPLE is the isolation battery's (`tools/isolation_samples.py`): every number 1, every text "x", every
option none, every list empty, every variant its first case. THE RICH SAMPLE fills everything the plain one leaves
out: every option holds a value, every list two items, every variant is its LAST case, every boolean true, and
every number, text and blob is distinct within its command, so a field read into its neighbour's place reads back
wrong. A number is 1,000 or more (two bytes of the canonical natural), an integer negative, a Nat64 past four
bytes, a text carries a two-byte character.

The export prints both, as the contract encodes them (`test/Export.export.mo`), and the reader decodes and
re-encodes each byte for byte and holds the rich and the plain sample's values to the ones written here
(`integration/oracle/typed_codec.py`). The compiler checks every sample against the command's type, so a family
whose type changes and whose samples do not cannot build; `--check` refuses a file that is not what this writes.

    python3 tools/codec_samples.py           write both files
    python3 tools/codec_samples.py --check   exit 1 when either is not what this writes

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import isolation_samples as S  # noqa: E402

ROOT = S.ROOT
OUT_MO = os.path.join(ROOT, 'test', 'CodecSamples.mo')
OUT_JSON = os.path.join(ROOT, 'test', 'fixtures', 'codec_samples.json')
SUBJECT = "0102031d"          # the principal both samples carry, as the export passes it
CO = 7                        # the company the plain sample names, as the export passes it


class Rich:
    """The rich value of a type: Motoko source and the value it reads back as, numbered field by field."""

    def __init__(self):
        self.k = 0

    def next(self):
        self.k += 1
        return self.k

    def value(self, mod, t):
        k = t[0]
        if k == 'name' and t[1] in S.PRIM:
            p, n = t[1], self.next()
            if p in ('Nat', 'Nat16', 'Nat32'):
                v = 1000 + 37 * n
                return '%d' % v, v
            if p == 'Nat8':
                v = 100 + n % 150
                return '%d' % v, v
            if p == 'Nat64':
                v = 2 ** 33 + n
                return '%d' % v, v
            if p == 'Int':
                v = -(3 * n + 1)
                return '%d' % v, v
            if p == 'Bool':
                return 'true', True
            if p == 'Text':
                v = 't%dé' % n
                return '"%s"' % v, v
            if p == 'Blob':
                b = bytes([0xde, 0xad, n % 256])
                return '"' + ''.join('\\%02x' % x for x in b) + '"', {'$blob': b.hex()}
            if p == 'Principal':
                return 'subject', {'$principal': SUBJECT}
            raise AssertionError(p)
        if k in ('name', 'path'):
            m, d = S.resolve(mod, t)
            return self.value(m, d)
        if k == 'opt':
            src, v = self.value(mod, t[1])
            return '?(%s)' % src, v
        if k == 'arr':
            a, av = self.value(mod, t[1])
            b, bv = self.value(mod, t[1])
            return '[%s, %s]' % (a, b), [av, bv]
        if k == 'tup':
            parts = [self.value(mod, x) for x in t[1]]
            return '(' + ', '.join(p[0] for p in parts) + ')', [p[1] for p in parts]
        if k == 'rec':
            if not t[1]:
                return '{}', {}
            parts = [(n, self.value(mod, ft)) for n, ft in t[1]]
            return '{ ' + '; '.join('%s = %s' % (n, p[0]) for n, p in parts) + ' }', {n: p[1] for n, p in parts}
        if k == 'var':
            n, pt = t[1][-1]
            if pt is None:
                return '#' + n, {'$case': n}
            src, v = self.value(mod, pt)
            return '#%s(%s)' % (n, src), {'$case': n, '$value': v}
        raise AssertionError(t)


def plain(mod, t, field=None):
    """The plain sample's value as it reads back, beside the isolation samples' source."""
    k = t[0]
    if k == 'name' and t[1] in S.PRIM:
        p = t[1]
        if field == 'companyId' and p == 'Nat':
            return CO
        return {'Nat': 1, 'Nat8': 1, 'Nat16': 1, 'Nat32': 1, 'Nat64': 1, 'Int': 0, 'Bool': False, 'Text': 'x',
                'Blob': {'$blob': '01'}, 'Principal': {'$principal': SUBJECT}}[p]
    if k in ('name', 'path'):
        m, d = S.resolve(mod, t)
        return plain(m, d, field)
    if k == 'opt':
        return None
    if k == 'arr':
        return []
    if k == 'tup':
        return [plain(mod, x) for x in t[1]]
    if k == 'rec':
        return {n: plain(mod, ft, n) for n, ft in t[1]}
    if k == 'var':
        n, pt = t[1][0]
        return {'$case': n} if pt is None else {'$case': n, '$value': plain(mod, pt)}
    raise AssertionError(t)


def build():
    cmd = S.module('Command')
    src, pos, _ = cmd.types['Command']
    arms = dict(S.Parser(src, pos).typ()[1])
    fam_src = S.strip_comments(open(os.path.join(ROOT, 'src', 'Command.mo')).read())
    fams = re.findall(r'"(\w+)"', re.search(r'public let FAMILIES : \[Text\] = \[(.*?)\];', fam_src, re.S).group(1))
    assert set(fams) == set(arms), set(fams) ^ set(arms)
    lines, expected = [], []
    for f in fams:
        t = arms[f]
        if t is None:
            lines.append('    #%s,' % f)
            expected.append({'family': f, 'plain': None, 'rich': None})
            continue
        r = Rich()
        src_v, rich_v = r.value(cmd, t)
        lines.append('    #%s(%s),' % (f, src_v))
        expected.append({'family': f, 'plain': plain(cmd, t), 'rich': rich_v})
    mo = '''// CodecSamples.mo - WRITTEN BY tools/codec_samples.py; do not edit by hand.
//
// The rich sample of every family in `Cmd.FAMILIES`, in that order: every option holding a value, every list two
// items, every variant its last case, every boolean true, and every number, text and blob distinct within its
// command. The value each reads back as is in test/fixtures/codec_samples.json.
//
// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Cmd "../src/Command";

module {
  public func rich(subject : Principal) : [Cmd.Command] = [
''' + '\n'.join(lines) + '''
  ];
}
'''
    js = json.dumps({'subject': SUBJECT, 'company': CO, 'families': expected}, ensure_ascii=False, indent=0,
                    sort_keys=True) + '\n'
    return fams, mo, js


def main():
    fams, mo, js = build()
    if '--check' in sys.argv:
        stale = [p for p, text in ((OUT_MO, mo), (OUT_JSON, js))
                 if not os.path.exists(p) or open(p, encoding='utf-8').read() != text]
        if stale:
            print('codec samples: %s not what tools/codec_samples.py writes' % ', '.join(os.path.relpath(p, ROOT) for p in stale))
            sys.exit(1)
        print('codec samples: %d families, current' % len(fams))
        return
    open(OUT_MO, 'w', encoding='utf-8').write(mo)
    open(OUT_JSON, 'w', encoding='utf-8').write(js)
    print('codec samples: %d families written' % len(fams))


if __name__ == '__main__':
    main()
