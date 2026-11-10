#!/usr/bin/env python3
"""
Classic-table <-> released-CDS-view field mapping lookup and best-effort
ABAP SELECT rewriter.

Data source: references/core-data-services.json — cdsName/tableName/released
plus per-field cdsField<->tableField pairs, read from an SAP system with the
ZCLEAN_CORE_SUCCESSORS report (release recorded in references/DATA_VERSION.json).
Fields computed in the view (CASE, literals, arithmetic, substrings) carry an
empty tableField. Output of the ZCLEAN_CORE_SUCCESSORS report also lists the columns
such a field reads, one row per column with computed=true: those rows are never
offered as a replacement. Verify non-trivial rewrites, see caveats in --help.

Usage:
    # Which released CDS view(s) exist for a classic table, and what's the field mapping?
    python3 lookup.py --table MARA

    # Which classic table+field does a CDS view+field come from?
    python3 lookup.py --cds I_PRODUCT --field Product

    # Best-effort rewrite of a simple classic SELECT into a CDS-based one
    python3 lookup.py --rewrite "SELECT SINGLE matnr FROM mara INTO @DATA(lv_matnr)."

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


SUCCESSOR_FILE = os.path.join(os.path.dirname(DATA_FILE), "successors.json")


def data_release(part="mapping"):
    try:
        with open(VERSION_FILE, encoding="utf-8") as f:
            version = json.load(f)
    except (OSError, ValueError):
        return "unknown"
    return (version.get(part) or {}).get("release") or version.get("release", "unknown")


def successors_of(name, object_type=None):
    try:
        with open(SUCCESSOR_FILE, encoding="utf-8") as f:
            rows = json.load(f)
    except OSError:
        return None
    pattern = re.compile("^" + re.escape(name.upper()).replace(r"\*", ".*") + "$")
    return [r for r in rows
            if pattern.match(r.get("objectName", "").upper())
            and (not object_type or r.get("objectType", "").upper() == object_type.upper())]


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


CLAUSE_ORDER = ("WHERE", "GROUP BY", "HAVING", "ORDER BY", "INTO", "APPENDING", "UP TO")
CLAUSE_RE = re.compile(r"\b(INTO|APPENDING|WHERE|GROUP\s+BY|HAVING|ORDER\s+BY|UP\s+TO)\b", re.IGNORECASE)


def split_clauses(rest):
    """Split the text after FROM <table> into its clauses, ignoring keywords inside literals."""
    marks = []
    for match in CLAUSE_RE.finditer(rest):
        if rest[:match.start()].count("'") % 2 == 0 and rest[:match.start()].count("`") % 2 == 0:
            marks.append(match)
    from_extra = rest[:marks[0].start()].strip() if marks else rest.strip()
    clauses = {}
    for index, match in enumerate(marks):
        end = marks[index + 1].start() if index + 1 < len(marks) else len(rest)
        key = " ".join(match.group(1).upper().split())
        clauses[key] = rest[match.end():end].strip()
    return from_extra, clauses


def rewrite_condition(text, view, known_columns, unmapped, in_expression):
    """Replace table columns in a WHERE/ORDER BY/... clause; leave literals and host variables alone."""
    def replace(match):
        name = match.group(1)
        if name.upper() not in known_columns:
            return name
        cds_f = cds_field_for_table(view, name)
        if cds_f:
            return cds_f
        if name not in unmapped:
            unmapped.append(name)
            used = expressions_using(view, name)
            if used:
                in_expression[name] = used
        return name

    parts = re.split(r"('(?:[^']|'')*'|`[^`]*`)", text)
    return "".join(part if index % 2 else
                   re.sub(r"(?<![@\w~\-])([A-Za-z_][A-Za-z0-9_]*)\b", replace, part)
                   for index, part in enumerate(parts))


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

    known_columns = {m.get("tableField", "").upper()
                     for v in views_for_table(data, table, allow_unreleased=True)
                     for m in v.get("mapping", []) if m.get("tableField")}

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

        from_extra, clauses = split_clauses(rest)
        # rewrite WHERE/other clause field references too (best-effort word-boundary replace)
        for key in ("WHERE", "GROUP BY", "HAVING", "ORDER BY"):
            if key in clauses:
                clauses[key] = rewrite_condition(clauses[key], view, known_columns, unmapped, in_expression)

        select_list = ", ".join(
            f"{cds_f}" if orig == "*" else f"{cds_f} AS {orig}"
            for orig, cds_f in field_mappings
        )
        single = "SINGLE " if m.group("single") else ""
        lines = [f"SELECT {single}{select_list}", f"  FROM {view['cdsName']}{' ' + from_extra if from_extra else ''}"]
        lines += [f"  {key} {clauses[key]}" for key in CLAUSE_ORDER if key in clauses]
        new_stmt = "\n".join(lines) + "."

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
    ap.add_argument("--object", help="Any object name (function module, class, data element, CDS view, table); "
                                     "* is a wildcard -> its successor(s)")
    ap.add_argument("--type", help="Object type filter for --object, e.g. FUNC, CLAS, DTEL, DDLS")
    args = ap.parse_args()

    if args.object:
        rows = successors_of(args.object, args.type)
        if rows is None:
            print(json.dumps({"error": "references/successors.json is missing"}, indent=2))
            sys.exit(1)
        print(json.dumps({"object": args.object.upper(), "dataRelease": data_release("successors"),
                          "note": "abapCloud: Released clears the ATC finding; Key user only and Not released do not.",
                          "successors": rows}, indent=2, ensure_ascii=False))
        return

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
