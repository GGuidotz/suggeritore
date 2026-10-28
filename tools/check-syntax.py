#!/usr/bin/env python3
"""Controllo di sintassi dei sorgenti Swift con tree-sitter (nel cloud swiftc non c'è). Segnala i nodi ERROR e MISSING.
    pip install tree-sitter tree-sitter-swift
    python3 -I tools/check-syntax.py            esce con 1 se trova errori
Non sostituisce la compilazione: tipi, API e disponibilità si verificano sul Mac con ./build.sh.
"""
import os, sys

try:
    import tree_sitter_swift
    from tree_sitter import Language, Parser
except ImportError:
    print("Installa: pip install tree-sitter tree-sitter-swift")
    sys.exit(2)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
parser = Parser(Language(tree_sitter_swift.language()))

def problems(node, out):
    if node.type == "ERROR" or node.is_missing:
        out.append(node)
    for child in node.children:
        problems(child, out)

bad = 0
files = 0
for base, _, names in os.walk(os.path.join(ROOT, "Sources")):
    for name in sorted(names):
        if not name.endswith(".swift"):
            continue
        files += 1
        path = os.path.join(base, name)
        source = open(path, "rb").read()
        tree = parser.parse(source)
        found = []
        problems(tree.root_node, found)
        for n in found:
            line = n.start_point[0] + 1
            snippet = source[n.start_byte:min(n.end_byte, n.start_byte + 60)].decode("utf-8", "replace").replace("\n", " ")
            kind = "MISSING" if n.is_missing else "ERROR"
            print(f"{os.path.relpath(path, ROOT)}:{line}: {kind} {snippet!r}")
            bad += 1
print(f"{files} file, {bad} problemi")
sys.exit(1 if bad else 0)
