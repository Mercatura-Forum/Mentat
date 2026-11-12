#!/usr/bin/env python3
"""ESG factors re-derived from the published files they name.

Every factor names its database, edition and the SHA-256 of
the published file, kept in the tree, so anyone can re-derive a certified ESG statement from public sources. This
tool is that derivation. It reads the two EPA files under `integration/esg/` - byte for byte the files their URLs
served, checked against `integration/esg/SOURCES.md` - and computes, with exact fractions, the integer facts each
factor carries: micrograms per its `per` units and kilojoules per the same, and the GWP set in thousandths. A mass
that is not a whole number of micrograms at its `per` is an error, never rounded; only the energy is rounded, half to
even, because the hub states it in mmBtu and a British thermal unit is not a whole number of joules.

  tools/esg_sources.py            check: the files' hashes, the derivation against integration/esg/factors.json,
                                  and every derived figure present as a literal in test/Esg.test.mo
  tools/esg_sources.py --write    re-derive integration/esg/factors.json

It reads the workbook with the standard library alone (a .xlsx is a zip of XML), so the check needs nothing installed.

Attribution: Thebes Core Team. Licence: Apache 2.0.
"""
import csv
from decimal import Decimal, ROUND_HALF_EVEN
import hashlib
import json
import os
import re
import sys
import zipfile
import xml.etree.ElementTree as ET
from fractions import Fraction
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
# ESG_DIR and ESG_BATTERY name a copy of the files and of the battery, for the control (tools/esg_sources_control.sh)
DIR = Path(os.environ.get("ESG_DIR", ROOT / "integration" / "esg"))
HUB = DIR / "ghg-emission-factors-hub-2025.xlsx"
SUPPLY = DIR / "SupplyChainGHGEmissionFactors_v1.3.0_NAICS_byGHG_USD2022.csv"
OUT = DIR / "factors.json"
BATTERY = Path(os.environ.get("ESG_BATTERY", ROOT / "test" / "Esg.test.mo"))

POUND_KG = Fraction("0.45359237")          # the international avoirdupois pound, exactly
MMBTU_KJ = Fraction("1055055.85262")       # 10^6 International Table Btu, exactly, in kJ
MWH_KJ = Fraction(3_600_000)
UG_PER_KG = 10 ** 9
UG_PER_G = 10 ** 6

NS = {"m": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


def sha256(p):
    return hashlib.sha256(p.read_bytes()).hexdigest()


def pinned():
    """The SHA-256 SOURCES.md records for each file."""
    out = {}
    for line in (DIR / "SOURCES.md").read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\| `([^`]+)` \| (\S+) \| ([0-9a-f]{64}) \|$", line)
        if m:
            out[m.group(1)] = m.group(3)
    return out


def cells(path):
    """Every cell of the workbook's first sheet, by coordinate, as the text the file stores."""
    with zipfile.ZipFile(path) as z:
        shared = []
        if "xl/sharedStrings.xml" in z.namelist():
            for si in ET.fromstring(z.read("xl/sharedStrings.xml")).findall("m:si", NS):
                shared.append("".join(t.text or "" for t in si.iter("{%s}t" % NS["m"])))
        sheet = ET.fromstring(z.read("xl/worksheets/sheet1.xml"))
    out = {}
    for c in sheet.iter("{%s}c" % NS["m"]):
        v = c.find("m:v", NS)
        if v is None:
            continue
        out[c.get("r")] = shared[int(v.text)] if c.get("t") == "s" else v.text
    return out


def sheet_number(text):
    """A numeric cell as the hub publishes it. The file stores a binary double's shortest round trip (0.05444 is
    `5.4440000000000001E-2`); a spreadsheet holds fifteen significant digits, so the cell is read to fifteen - the
    figure the hub prints - and then exactly."""
    d = Decimal(text)
    if d == 0:
        return Fraction(0)
    q = Decimal(1).scaleb(d.adjusted() - 14)
    return Fraction(d.quantize(q, rounding=ROUND_HALF_EVEN).normalize())


def exact(x, what):
    if x.denominator != 1:
        raise SystemExit(f"esg_sources: {what} is {x}, not a whole number")
    return int(x)


def half_even(x):
    q, r = divmod(x.numerator, x.denominator)
    if 2 * r > x.denominator or (2 * r == x.denominator and q % 2 == 1):
        q += 1
    return q


def derive():
    hub = cells(HUB)

    def num(ref, label_ref=None, label=None):
        if label_ref is not None and hub.get(label_ref, "").strip() != label:
            raise SystemExit(f"esg_sources: {label_ref} reads {hub.get(label_ref)!r}, not {label!r}: the hub is not the file this reads")
        return sheet_number(hub[ref])

    gwp = [
        {"gas": "CO2", "group": "co2", "gwpMilli": 1000, "reference": "Table 11: carbon dioxide, by definition"},
        {"gas": "CH4", "group": "ch4", "gwpMilli": exact(num("E525", "D525", "CH4") * 1000, "CH4's GWP"), "reference": "Table 11, E525"},
        {"gas": "N2O", "group": "n2o", "gwpMilli": exact(num("E526", "D526", "N2O") * 1000, "N2O's GWP"), "reference": "Table 11, E526"},
        {"gas": "HFCs and PFCs, unspecified", "group": "hfc", "gwpMilli": 1000,
         "reference": "Supply Chain v1.3.0: given in kg CO2e, so its potential is one"},
    ]

    per_ng = 1_000_000  # scf
    ng = {
        "code": "ng", "database": "EPA GHG Emission Factors Hub", "edition": "2025", "file": HUB.name,
        "reference": "Table 1, Natural Gas (row 38): H38 kg CO2/scf, I38 g CH4/scf, J38 g N2O/scf, D38 mmBtu/scf",
        "scope": "scope1", "category": 1, "basis": "physical", "unit": "scf", "per": per_ng,
        "gases": [
            {"gas": "CO2", "micrograms": exact(num("H38", "C38", "Natural Gas") * UG_PER_KG * per_ng, "natural gas CO2")},
            {"gas": "CH4", "micrograms": exact(num("I38") * UG_PER_G * per_ng, "natural gas CH4")},
            {"gas": "N2O", "micrograms": exact(num("J38") * UG_PER_G * per_ng, "natural gas N2O")},
        ],
        "energySource": "naturalGas", "kilojoules": half_even(num("D38") * MMBTU_KJ * per_ng),
    }

    per_grid = 100_000  # kWh, which is 100 MWh
    mwh = Fraction(per_grid, 1000)
    grid = {
        "code": "grid", "database": "EPA GHG Emission Factors Hub (eGRID2023)", "edition": "2025", "file": HUB.name,
        "reference": "Table 6, US Average (row 366): E366 lb CO2/MWh, F366 lb CH4/MWh, G366 lb N2O/MWh",
        "scope": "scope2Location", "category": 0, "basis": "physical", "unit": "kWh", "per": per_grid,
        "gases": [
            {"gas": "CO2", "micrograms": exact(num("E366", "C366", "US Average") * POUND_KG * UG_PER_KG * mwh, "grid CO2")},
            {"gas": "CH4", "micrograms": exact(num("F366") * POUND_KG * UG_PER_KG * mwh, "grid CH4")},
            {"gas": "N2O", "micrograms": exact(num("G366") * POUND_KG * UG_PER_KG * mwh, "grid N2O")},
        ],
        "energySource": "gridUnspecified", "kilojoules": exact(MWH_KJ * mwh, "grid energy"),
    }

    rows = {}
    with SUPPLY.open(newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            if r["2017 NAICS Code"] == "324110":
                rows[r["GHG"]] = r
    names = {"Carbon dioxide": "CO2", "Methane": "CH4", "HFCs and PFCs, unspecified": "HFCs and PFCs, unspecified"}
    per_usd = 100  # cents
    refinery = {
        "code": "refinery", "database": "EPA Supply Chain GHG Emission Factors", "edition": "v1.3.0, 2022 USD", "file": SUPPLY.name,
        "reference": "NAICS 324110 Petroleum Refineries, Supply Chain Emission Factors with Margins",
        "scope": "scope3", "category": 1, "basis": "monetary", "unit": "USD", "per": per_usd,
        "gases": [
            {"gas": names[g], "micrograms": exact(Fraction(rows[g]["Supply Chain Emission Factors with Margins"]) * UG_PER_KG, "refinery " + g)}
            for g in ["Carbon dioxide", "Methane", "HFCs and PFCs, unspecified"]
        ],
        "energySource": "none", "kilojoules": 0,
    }
    for g in ["Carbon dioxide", "Methane"]:
        if not rows[g]["Unit"].startswith("kg/2022 USD"):
            raise SystemExit(f"esg_sources: {g} is in {rows[g]['Unit']!r}, not kg per 2022 USD")
    if not rows["HFCs and PFCs, unspecified"]["Unit"].startswith("kg CO2e/2022 USD"):
        raise SystemExit("esg_sources: the unspecified HFCs and PFCs are no longer given in kg CO2e")

    return {
        "sources": {HUB.name: sha256(HUB), SUPPLY.name: sha256(SUPPLY)},
        "gwpSet": {"name": "IPCC AR5, 100-year", "database": "EPA GHG Emission Factors Hub", "edition": "2025", "file": HUB.name, "gases": gwp},
        "factors": [ng, grid, refinery],
    }


def literal(n):
    """A Nat as Motoko spells it with thousands separators."""
    s = str(n)
    parts = []
    while len(s) > 3:
        parts.insert(0, s[-3:])
        s = s[:-3]
    parts.insert(0, s)
    return "_".join(parts)


def main():
    pins = pinned()
    bad = []
    for p in (HUB, SUPPLY):
        if pins.get(p.name) != sha256(p):
            bad.append(f"{p.name}: SHA-256 {sha256(p)}, SOURCES.md says {pins.get(p.name)}")
    if bad:
        print("\n".join("ESG SOURCES: " + b for b in bad))
        sys.exit(1)
    d = derive()
    text = json.dumps(d, indent=2, ensure_ascii=False) + "\n"
    if "--write" in sys.argv[1:]:
        OUT.write_text(text, encoding="utf-8")
        print(f"esg sources: {len(d['factors'])} factors and a GWP set of {len(d['gwpSet']['gases'])} written")
        return
    if not OUT.exists() or OUT.read_text(encoding="utf-8") != text:
        print("ESG SOURCES: integration/esg/factors.json is not what the files derive (tools/esg_sources.py --write)")
        sys.exit(1)
    battery = BATTERY.read_text(encoding="utf-8")
    figures = [(f["code"] + " " + g["gas"], g["micrograms"]) for f in d["factors"] for g in f["gases"]]
    figures += [(f["code"] + " kilojoules", f["kilojoules"]) for f in d["factors"] if f["kilojoules"]]
    figures += [(g["gas"] + " GWP", g["gwpMilli"]) for g in d["gwpSet"]["gases"]]
    missing = [(w, v) for (w, v) in figures if not re.search(r"(?<![0-9_])" + re.escape(literal(v)) + r"(?![0-9_])", battery)]
    for w, v in missing:
        print(f"ESG SOURCES: the battery does not weigh by {w} = {literal(v)}")
    print(f"count: ESG figures derived from the published files = {len(figures)}")
    print(f"count: ESG figures the battery weighs by = {len(figures) - len(missing)}")
    if missing:
        sys.exit(1)
    print("ESG SOURCES GREEN")


if __name__ == "__main__":
    main()
