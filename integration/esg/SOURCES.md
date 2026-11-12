# The published emission factors

Two files from the United States Environmental Protection Agency, read 2026-11-11 (each HTTP 200). Works of the
United States Government, they are in the public domain (17 U.S.C. §105), and are carried here byte for byte.

| File | Source | SHA-256 |
|---|---|---|
| `ghg-emission-factors-hub-2025.xlsx` | https://www.epa.gov/system/files/other-files/2025-01/ghg-emission-factors-hub-2025.xlsx | 43afb91d79b2ae765b3a447549d9e1021a144a407cec5eb804be9fcf69a668a7 |
| `SupplyChainGHGEmissionFactors_v1.3.0_NAICS_byGHG_USD2022.csv` | https://pasteur.epa.gov/uploads/10.23719/1531143/SupplyChainGHGEmissionFactors_v1.3.0_NAICS_byGHG_USD2022.csv | 963952e5911dd5c5a4408172192b327c1583b5491a5b80c2d7cb03260411ee16 |

The first is the GHG Emission Factors Hub (2025 edition): stationary and mobile combustion, eGRID2023 electricity,
steam, and the scope-3 transport, waste and travel factors, with the IPCC AR5 100-year global warming potentials it
weighs them by (Table 11). The second is the Supply Chain GHG Emission Factors for US Commodities and Industries,
v1.3.0, by gas, per 2022 US dollar at purchaser price - the spend-based factors a posted line is weighed by.

`tools/esg_sources.py` re-derives, from these files alone, the integer facts every seeded factor carries - micrograms
of each gas and kilojoules per the factor's stated quantity, and the GWPs in thousandths - into `factors.json`, and
the gate holds both the files (to these hashes) and the derivation (to `factors.json` and to the figures the battery
weighs by). A factor version recorded on the chain names the same database, edition and SHA-256, so a reader holding
a sealed statement fetches the file, checks its hash and repeats the arithmetic.

The arithmetic is exact. A cell of the workbook is read to the fifteen significant digits a spreadsheet holds - the
file stores 0.05444 as the binary double `5.4440000000000001E-2`, and fifteen digits give back the figure the hub
prints - and then as an exact decimal. A mass is a whole number of micrograms at the factor's `per` or the derivation stops; the
pound is 0.45359237 kg exactly. Energy alone is rounded, half to even, at the factor's `per`: the hub states fuels in
mmBtu, and 10^6 International Table Btu is 1,055,055.85262 kJ, so natural gas at 0.001026 mmBtu per scf carries
1,082,487,304.78812 kJ per million scf, held as 1,082,487,305.

Attribution: Thebes Core Team.
