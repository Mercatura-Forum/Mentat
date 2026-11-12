#!/usr/bin/env python3
"""Writes test/IsolationSamples.mo: one command of every family in `Cmd.FAMILIES`, in that order, built from the
command's own type, for the isolation battery (test/Isolation.test.mo).

Every value is the plainest one its type admits - a number is 1, a text "x", an option none, a list empty, a
variant its first case - except that every field named `companyId` carries the battery's company and every
principal the battery's subject, so each act names the company the probe acts in. The sample is never meant to
be accepted by its fold: it is meant to reach the gate, which must refuse a stranger and a member without the
holders' roles before any fold is asked. The compiler checks every sample against the command's type, so a
family whose type changes and whose sample does not cannot build.

    python3 tools/isolation_samples.py           write the file
    python3 tools/isolation_samples.py --check   exit 1 when the file is not what this writes

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import glob, os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'test', 'IsolationSamples.mo')


def strip_comments(s):
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    return re.sub(r'//[^\n]*', '', s)


class Module:
    def __init__(self, path):
        self.path = path
        src = strip_comments(open(path).read())
        self.imports = dict(re.findall(r'import\s+(\w+)\s+"([^"]+)"', src))
        self.types = {}
        for m in re.finditer(r'public\s+type\s+(\w+)(\s*<[^>]*>)?\s*=\s*', src):
            self.types[m.group(1)] = (src, m.end(), m.group(2))


MODULES = {}


def module(name):
    path = os.path.join(ROOT, 'src', name + '.mo')
    if path not in MODULES:
        MODULES[path] = Module(path)
    return MODULES[path]


class Parser:
    """A Motoko type expression, enough of it for the command types: records, variants, options, arrays,
    tuples and named types."""

    def __init__(self, src, pos):
        self.s, self.i = src, pos

    def ws(self):
        while self.i < len(self.s) and self.s[self.i] in ' \t\r\n':
            self.i += 1

    def peek(self):
        self.ws()
        return self.s[self.i] if self.i < len(self.s) else ''

    def eat(self, t):
        self.ws()
        assert self.s.startswith(t, self.i), (t, self.s[self.i:self.i + 60])
        self.i += len(t)

    def ident(self):
        self.ws()
        m = re.compile(r'[A-Za-z_][A-Za-z0-9_]*').match(self.s, self.i)
        assert m, self.s[self.i:self.i + 60]
        self.i = m.end()
        return m.group(0)

    def typ(self):
        c = self.peek()
        if c == '?':
            self.eat('?')
            return ('opt', self.typ())
        if c == '[':
            self.eat('[')
            self.ws()
            if self.s.startswith('var ', self.i):
                self.i += 4
            t = self.typ()
            self.eat(']')
            return ('arr', t)
        if c == '(':
            self.eat('(')
            items = []
            while self.peek() != ')':
                items.append(self.typ())
                if self.peek() == ',':
                    self.eat(',')
            self.eat(')')
            return items[0] if len(items) == 1 else ('tup', items)
        if c == '{':
            self.eat('{')
            if self.peek() == '#':
                alts = []
                while self.peek() != '}':
                    self.eat('#')
                    n = self.ident()
                    t = None
                    if self.peek() == ':':
                        self.eat(':')
                        t = self.typ()
                    alts.append((n, t))
                    if self.peek() == ';':
                        self.eat(';')
                self.eat('}')
                return ('var', alts)
            fields = []
            while self.peek() != '}':
                self.ws()
                if self.s.startswith('var ', self.i):
                    self.i += 4
                n = self.ident()
                self.eat(':')
                fields.append((n, self.typ()))
                if self.peek() == ';':
                    self.eat(';')
            self.eat('}')
            return ('rec', fields)
        name = self.ident()
        if self.peek() == '.':
            self.eat('.')
            return ('path', name, self.ident())
        if self.peek() == '<':
            depth = 0
            while True:
                ch = self.s[self.i]
                depth += ch == '<'
                depth -= ch == '>'
                self.i += 1
                if depth == 0:
                    break
        return ('name', name)


PRIM = {'Nat': '1', 'Nat8': '1', 'Nat16': '1', 'Nat32': '1', 'Nat64': '1', 'Int': '0', 'Int8': '0', 'Int16': '0',
        'Int32': '0', 'Int64': '0', 'Text': '"x"', 'Bool': 'false', 'Blob': '"\\01"', 'Principal': 'subject',
        'Float': '0.0', 'Char': "'x'"}


def resolve(mod, t):
    """The definition a named type stands for, in the module that declares it."""
    if t[0] == 'path':
        target = mod.imports.get(t[1])
        assert target and not target.startswith('mo:'), ('a type from outside the tree', t, mod.path)
        m = module(os.path.basename(target))
        name = t[2]
    else:
        m, name = mod, t[1]
    assert name in m.types, (name, m.path)
    src, pos, _ = m.types[name]
    return m, Parser(src, pos).typ()


def value(mod, t, field=None):
    k = t[0]
    if k == 'name' and t[1] in PRIM:
        if field == 'companyId':
            return 'co'
        return PRIM[t[1]]
    if k in ('name', 'path'):
        m, d = resolve(mod, t)
        return value(m, d, field)
    if k == 'opt':
        return 'null'
    if k == 'arr':
        return '[]'
    if k == 'tup':
        return '(' + ', '.join(value(mod, x) for x in t[1]) + ')'
    if k == 'rec':
        if not t[1]:
            return '{}'
        return '{ ' + '; '.join('%s = %s' % (n, value(mod, ft, n)) for n, ft in t[1]) + ' }'
    if k == 'var':
        n, pt = t[1][0]
        return '#' + n if pt is None else '#%s(%s)' % (n, value(mod, pt))
    raise AssertionError(t)


def main():
    cmd = module('Command')
    src, pos, _ = cmd.types['Command']
    command = Parser(src, pos).typ()
    arms = dict(command[1])
    fam_src = strip_comments(open(os.path.join(ROOT, 'src', 'Command.mo')).read())
    fams = re.findall(r'"(\w+)"', re.search(r'public let FAMILIES : \[Text\] = \[(.*?)\];', fam_src, re.S).group(1))
    assert set(fams) == set(arms), set(fams) ^ set(arms)
    lines = []
    for f in fams:
        t = arms[f]
        lines.append('    #%s(%s),' % (f, value(cmd, t)) if t is not None else '    #%s,' % f)
    out = '''// IsolationSamples.mo - WRITTEN BY tools/isolation_samples.py; do not edit by hand.
//
// One command of every family in `Cmd.FAMILIES`, in that order, each the plainest value its type admits, with
// every `companyId` the battery's company and every principal the battery's subject.
//
// Attribution: Thebes Core Team. Licence: Apache 2.0.

import Cmd "../src/Command";

module {
  public func samples(co : Nat, subject : Principal) : [Cmd.Command] = [
''' + '\n'.join(lines) + '''
  ];
}
'''
    if '--check' in sys.argv:
        if not os.path.exists(OUT) or open(OUT).read() != out:
            print('test/IsolationSamples.mo is not what tools/isolation_samples.py writes')
            sys.exit(1)
        print('isolation samples: %d families, current' % len(fams))
        return
    open(OUT, 'w').write(out)
    print('isolation samples: %d families written' % len(fams))


if __name__ == '__main__':
    main()
