#!/usr/bin/env python3
"""Comprueba las traducciones de la interfaz (lo ejecuta el CI; no necesita macOS).

Los textos del código van como L("English text") (ver Sources/PinVol/Strings.swift): el inglés es el idioma base y la
clave. Cada idioma extra es una carpeta Resources/<código>.lproj con su Localizable.strings e InfoPlist.strings.
Falla si:
  · un texto del código no tiene traducción en algún idioma, o una traducción ya no se usa;
  · hay claves repetidas, líneas que no se entienden o claves con interpolación de Swift ("\\(...)");
  · una traducción usa otros especificadores de formato (%@, %ld, %d…) que el texto en inglés;
  · las claves de InfoPlist.strings no coinciden entre idiomas, no están en Info.plist, o un idioma no figura en
    CFBundleLocalizations (que además debe incluir el inglés y ser el CFBundleDevelopmentRegion).

Uso: python3 tools/check-strings.py
"""
import plistlib
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Sources" / "PinVol"
RES = ROOT / "Resources"
BASE = "en"

LITERAL = r'"((?:[^"\\]|\\.)*)"'
CALL = re.compile(r'\bL\(\s*' + LITERAL)
LINE = re.compile(r'^\s*' + LITERAL + r'\s*=\s*' + LITERAL + r'\s*;\s*$')
FORMAT = re.compile(r'%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ld|lu|lld|d|u|f|@|s)')
ESCAPES = {'"': '"', "\\": "\\", "n": "\n", "t": "\t"}

errors = []


def rel(path):
    return path.relative_to(ROOT)


def unescape(raw, where):
    out, i = [], 0
    while i < len(raw):
        c = raw[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        nxt = raw[i + 1] if i + 1 < len(raw) else ""
        if nxt == "(":
            errors.append(f'{where}: la clave lleva interpolación de Swift; usa un especificador de formato: "{raw}"')
            return raw
        if nxt not in ESCAPES:
            errors.append(f'{where}: escape no admitido "\\{nxt}" en "{raw}"')
            return raw
        out.append(ESCAPES[nxt])
        i += 2
    return "".join(out)


def code_keys():
    keys = {}
    for path in sorted(SOURCES.glob("*.swift")):
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            for m in CALL.finditer(line):
                where = f"{rel(path)}:{n}"
                keys.setdefault(unescape(m.group(1), where), where)
    return keys


def parse_strings(path):
    """Lee un .strings en formato de texto («"clave" = "valor";»), con comentarios /* */ y //."""
    table = {}
    if not path.exists():
        errors.append(f"Falta {rel(path)}")
        return table
    text = re.sub(r"/\*.*?\*/", "", path.read_text(encoding="utf-8"), flags=re.S)
    for n, line in enumerate(text.splitlines(), 1):
        stripped = line.strip()
        if not stripped or stripped.startswith("//"):
            continue
        where = f"{rel(path)}:{n}"
        m = LINE.match(line)
        if not m:
            errors.append(f"{where}: línea no válida: {stripped}")
            continue
        key, value = unescape(m.group(1), where), unescape(m.group(2), where)
        if key in table:
            errors.append(f'{where}: clave repetida: "{key}"')
        table[key] = value
    return table


def formats(s):
    return Counter(FORMAT.findall(s))


def main():
    used = code_keys()
    info = plistlib.loads((ROOT / "Info.plist").read_bytes())
    declared = info.get("CFBundleLocalizations", [])
    if info.get("CFBundleDevelopmentRegion") != BASE:
        errors.append(f"Info.plist: CFBundleDevelopmentRegion debe ser {BASE}")
    if BASE not in declared:
        errors.append(f"Info.plist: CFBundleLocalizations debe incluir {BASE}")

    base_info = parse_strings(RES / f"{BASE}.lproj" / "InfoPlist.strings")
    for key in base_info:
        if key not in info:
            errors.append(f"{rel(RES / f'{BASE}.lproj' / 'InfoPlist.strings')}: {key} no está en Info.plist")

    langs = sorted(p.name[: -len(".lproj")] for p in RES.glob("*.lproj") if p.name != f"{BASE}.lproj")
    if not langs:
        errors.append("No hay ningún idioma además del inglés en Resources/")
    for lang in langs:
        if lang not in declared:
            errors.append(f"Info.plist: CFBundleLocalizations no incluye {lang}")
        path = RES / f"{lang}.lproj" / "Localizable.strings"
        table = parse_strings(path)
        for key, where in used.items():
            if key not in table:
                errors.append(f'{where}: falta la traducción ({lang}) de "{key}" en {rel(path)}')
        for key, value in table.items():
            if key not in used:
                errors.append(f'{rel(path)}: la clave "{key}" ya no se usa en el código')
            elif formats(key) != formats(value):
                errors.append(f'{rel(path)}: "{key}" y su traducción usan distintos especificadores de formato '
                              f"({dict(formats(key))} frente a {dict(formats(value))})")
        lang_info = parse_strings(RES / f"{lang}.lproj" / "InfoPlist.strings")
        if set(lang_info) != set(base_info):
            errors.append(f"InfoPlist.strings: las claves de {BASE}.lproj y {lang}.lproj no coinciden "
                          f"({sorted(set(lang_info) ^ set(base_info))})")

    if errors:
        print("\n".join(errors), file=sys.stderr)
        print(f"\n{len(errors)} problema(s) con las traducciones.", file=sys.stderr)
        return 1
    print(f"OK: {len(used)} textos de la interfaz, traducidos a: {', '.join(langs)}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
