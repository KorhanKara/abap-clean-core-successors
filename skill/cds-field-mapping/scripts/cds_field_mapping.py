#!/usr/bin/env python3
"""
Classic-table <-> released-CDS-view field mapping lookup and best-effort
ABAP SELECT rewriter.

Data source: references/core-data-services.json — cdsName/tableName/released
plus per-field cdsField<->tableField pairs, read from an SAP system with the
ZCDS_FIELD_MAPPING report (release recorded in references/DATA_VERSION.json).
Fields computed in the view (CASE, literals, arithmetic, substrings) carry an
empty tableField. Output of the ZCDS_FIELD_MAPPING report also lists the columns
such a field reads, one row per column with computed=true: those rows are never
offered as a replacement. Verify non-trivial rewrites, see caveats in --help.

Usage:
    # Which released CDS view(s) exist for a classic table, and what's the field mapping?
    python3 cds_field_mapping.py --table MARA

    # Which classic table+field does a CDS view+field come from?
    python3 cds_field_mapping.py --cds I_PRODUCT --field Product

    # Best-effort rewrite of a simple classic SELECT into a CDS-based one
    python3 cds_field_mapping.py --rewrite "SELECT SINGLE matnr FROM mara INTO @DATA(lv_matnr)."

Only entities with released=true are used for rewrite suggestions by
default (pass --allow-unreleased to also consider not-yet-released CDS
views, e.g. for awareness, not for production code).
"""
import json
import re
import sys
import argparse
import os

DATA_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         os.pardir, "references", "core-data-services.json")


VERSION_FILE = os.path.join(os.path.dirname(DATA_FILE), "DATA_VERSION.json")


def load():
    with open(DATA_FILE, encoding="utf-8") as f:
        return json.load(f)


def data_release():
    try:
        with open(VERSION_FILE, encoding="utf-8") as f:
            return json.load(f).get("release", "unknown")
    except (OSError, ValueError):
        return "unknown"


def tidy(expression):
    return " ".join((expression or "").split())


def views_for_table(data, table_name, allow_unreleased=False):
    table_name = table_name.upper()
    out = []
    for v in data:
        if v.get("tableName", "").upper() != table_name:
            continue
        if not allow_unreleased and not v.get("released"):
            continue
        out.append(v)
    return out


def table_field_for_cds(data, cds_name, field_name):
    cds_name = cds_name.upper()
    for v in data:
        if v.get("cdsName", "").upper() != cds_name:
            continue
        rows = [m for m in v.get("mapping", []) if m.get("cdsField", "").upper() == field_name.upper()]
        if rows:
            return v, rows
    return None, []


def cds_field_for_table(view, field_name):
    for m in view.get("mapping", []):
        if m.get("computed"):
            continue
        if m.get("tableField", "").upper() == field_name.upper():
            return m.get("cdsField")
    return None


def expressions_using(view, field_name):
    return [{"cdsField": m.get("cdsField"), "expression": tidy(m.get("expression")), "definedIn": m.get("definedIn")}
            for m in view.get("mapping", [])
            if m.get("computed") and m.get("tableField", "").upper() == field_name.upper()]


SELECT_RE = re.compile(
    r"""SELECT\s+
        (?P<single>SINGLE\s+)?
        (?P<fields>.+?)\s+
        FROM\s+(?P<table>[\w/]+)\s*
        (?P<rest>.*)
    """,
    re.IGNORECASE | re.VERBOSE | re.DOTALL,
)


def rewrite_select(data, statement, allow_unreleased=False):
    stmt = statement.strip().rstrip(".")
    m = SELECT_RE.match(stmt)
    if not m:
        return {"error": "Could not parse as a simple 'SELECT [SINGLE] field... FROM table ...' statement. "
                          "Complex joins/subqueries/dynamic SELECTs need manual review."}
    table = m.group("table")
    fields_raw = m.group("fields").strip()
    rest = m.group("rest").strip()
    fields = [f.strip().rstrip(",") for f in re.split(r"[,\s]+", fields_raw) if f.strip()]

    candidates = views_for_table(data, table, allow_unreleased=allow_unreleased)
    if not candidates:
        return {"error": f"No {'​' if allow_unreleased else 'released '}CDS view found in the mapping for table '{table}'. "
                          f"It may not be covered by this dataset, or genuinely have no CDS successor yet."}

    results = []
    for view in candidates:
        field_mappings = []
        unmapped = []
        in_expression = {}
        for f in fields:
            if f == "*":
                field_mappings.append(("*", "*"))
                continue
            cds_f = cds_field_for_table(view, f)
            if cds_f:
                field_mappings.append((f, cds_f))
            else:
                unmapped.append(f)
                used = expressions_using(view, f)
                if used:
                    in_expression[f] = used

        # rewrite WHERE/other clause field references too (best-effort word-boundary replace)
        rewritten_rest = rest
        for f, cds_f in field_mappings:
            if f == "*":
                continue
            rewritten_rest = re.sub(rf"\b{re.escape(f)}\b", cds_f, rewritten_rest, flags=re.IGNORECASE)

        select_list = ", ".join(
            f"{cds_f}" if orig == "*" else f"{cds_f} AS {orig}"
            for orig, cds_f in field_mappings
        )
        single = "SINGLE " if m.group("single") else ""
        new_stmt = f"SELECT {single}{select_list} FROM {view['cdsName']} {rewritten_rest}".strip()
        if not new_stmt.endswith("."):
            new_stmt += "."

        result = {
            "cdsView": view["cdsName"],
            "released": view.get("released"),
            "rewritten": new_stmt,
            "unmappedFields": unmapped,
        }
        if in_expression:
            result["usedInExpression"] = in_expression
        results.append(result)

    results.sort(key=lambda r: len(r["unmappedFields"]))
    return {"originalTable": table.upper(), "dataRelease": data_release(),
            "note": "Candidates are sorted by fewest unmapped fields.", "candidates": results}


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--table", help="Classic table name -> list released CDS view(s) + full field mapping")
    ap.add_argument("--cds", help="CDS view name (use with --field) -> underlying table field")
    ap.add_argument("--field", help="Field name, used with --table or --cds")
    ap.add_argument("--rewrite", help="A simple classic ABAP SELECT statement to rewrite against a CDS view")
    ap.add_argument("--allow-unreleased", action="store_true", help="Also consider not-yet-released CDS views")
    args = ap.parse_args()

    data = load()

    if args.rewrite:
        print(json.dumps(rewrite_select(data, args.rewrite, args.allow_unreleased), indent=2, ensure_ascii=False))
    elif args.table and args.field:
        views = views_for_table(data, args.table, args.allow_unreleased)
        out = []
        for v in views:
            cds_f = cds_field_for_table(v, args.field)
            row = {"cdsView": v["cdsName"], "released": v.get("released"), "cdsField": cds_f}
            used = expressions_using(v, args.field) if not cds_f else []
            if used:
                row["usedInExpression"] = used
            out.append(row)
        print(json.dumps({"table": args.table.upper(), "field": args.field, "dataRelease": data_release(),
                          "results": out}, indent=2, ensure_ascii=False))
    elif args.table:
        views = views_for_table(data, args.table, args.allow_unreleased)
        print(json.dumps({"table": args.table.upper(), "views": views}, indent=2, ensure_ascii=False))
    elif args.cds and args.field:
        view, rows = table_field_for_cds(data, args.cds, args.field)
        if not view:
            print(json.dumps({"found": False}, indent=2))
        else:
            computed = [m for m in rows if m.get("computed")]
            result = {"found": True, "cdsView": view["cdsName"], "tableName": view["tableName"],
                      "released": view.get("released"), "dataRelease": data_release(),
                      "computed": bool(computed),
                      "tableField": next((m.get("tableField") for m in rows if not m.get("computed")), "")}
            if computed:
                result["readsColumns"] = [m.get("tableField") for m in computed]
                result["expression"] = tidy(computed[0].get("expression"))
                result["definedIn"] = computed[0].get("definedIn")
            print(json.dumps(result, indent=2, ensure_ascii=False))
    else:
        ap.print_help()
        sys.exit(1)


if __name__ == "__main__":
    main()
