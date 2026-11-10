#!/usr/bin/env python3
"""
Install a file downloaded from the ZCDS_FIELD_MAPPING report (Download JSON) as
this skill's data.

Usage:
    python3 import_mapping.py core-data-services.json [--release "S4CORE 109 SP01"]

The file holds the table field mapping ("tables") and the successor list
("successors"). They are written to references/core-data-services.json and
references/successors.json, and the release the report read from the system
is recorded in references/DATA_VERSION.json. A file from an older report
version (a plain list of tables) is accepted too. The previous files are kept
with a .bak suffix.
"""
import argparse
import datetime
import json
import os
import shutil
import sys

_REF = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "references"))
MAPPING_FILE = os.path.join(_REF, "core-data-services.json")
SUCCESSOR_FILE = os.path.join(_REF, "successors.json")
VERSION_FILE = os.path.join(_REF, "DATA_VERSION.json")


def load_export(path):
    with open(path, encoding="utf-8-sig") as f:
        data = json.load(f)
    if isinstance(data, list):
        return {"tables": data, "successors": None, "release": None, "pairsFrom": None}
    if isinstance(data, dict) and isinstance(data.get("tables"), list):
        return data
    sys.exit("expected the JSON file written by ZCDS_FIELD_MAPPING")


def check_tables(views):
    if not views:
        sys.exit("the file holds no table mapping")
    for view in views:
        if not {"cdsName", "tableName", "released", "mapping"} <= view.keys():
            sys.exit(f"unexpected entry shape: {sorted(view.keys())}")
        for row in view["mapping"]:
            if not {"cdsField", "tableField"} <= row.keys():
                sys.exit(f"unexpected mapping row in {view['cdsName']}: {sorted(row.keys())}")


def check_successors(rows):
    for row in rows:
        if not {"objectType", "objectName", "successorType", "successorName", "abapCloud"} <= row.keys():
            sys.exit(f"unexpected successor row: {sorted(row.keys())}")


def write_json(path, data):
    if os.path.exists(path):
        shutil.copyfile(path, path + ".bak")
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")


def summarize(views):
    return {
        "views": len(views),
        "fields": sum(len({m["cdsField"] for m in v["mapping"]}) for v in views),
        "mappedFields": sum(1 for v in views for m in v["mapping"] if m["tableField"] and not m.get("computed")),
        "inExpressionFields": sum(len({m["cdsField"] for m in v["mapping"] if m.get("computed")}) for v in views),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("file", help="JSON file written by ZCDS_FIELD_MAPPING with Download JSON")
    parser.add_argument("--release", help="label for the data; default: the release stored in the file")
    args = parser.parse_args()

    export = load_export(args.file)
    check_tables(export["tables"])
    successors = export.get("successors")
    if successors:
        check_successors(successors)

    try:
        with open(VERSION_FILE, encoding="utf-8") as f:
            version = json.load(f)
    except (OSError, ValueError):
        version = {}

    write_json(MAPPING_FILE, export["tables"])
    summary = summarize(export["tables"])
    version["mapping"] = {"source": "ZCDS_FIELD_MAPPING report, Download JSON",
                          "release": (args.release or export.get("release") or "").strip() or "user's own system",
                          "pairsFrom": export.get("pairsFrom") or "unknown",
                          "generated": datetime.date.today().isoformat(),
                          **summary}

    if successors:
        write_json(SUCCESSOR_FILE, successors)
        version["successors"] = {"source": "ZCDS_FIELD_MAPPING report, Download JSON",
                                 "release": version["mapping"]["release"],
                                 "generated": version["mapping"]["generated"],
                                 "rows": len(successors)}
        summary["successors"] = len(successors)
    else:
        summary["successors"] = "not in the file, kept the existing list"

    with open(VERSION_FILE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(version, f, indent=2)
        f.write("\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
