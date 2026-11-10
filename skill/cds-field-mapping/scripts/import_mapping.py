#!/usr/bin/env python3
"""
Install a mapping file downloaded from the ZCDS_FIELD_MAPPING report as
references/core-data-services.json and record it in references/DATA_VERSION.json.

Usage:
    python3 import_mapping.py core-data-services.json [--release "S4CORE 109 SP01"]

The previous file is kept as core-data-services.json.bak.
"""
import argparse
import datetime
import json
import os
import shutil
import sys

_REF = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "references"))
TARGET = os.path.join(_REF, "core-data-services.json")
VERSION_FILE = os.path.join(_REF, "DATA_VERSION.json")


def load_views(path):
    with open(path, encoding="utf-8-sig") as f:
        views = json.load(f)
    if not isinstance(views, list) or not views:
        sys.exit("expected a non-empty JSON array")
    for view in views:
        if not {"cdsName", "tableName", "released", "mapping"} <= view.keys():
            sys.exit(f"unexpected entry shape: {sorted(view.keys())}")
        for row in view["mapping"]:
            if not {"cdsField", "tableField"} <= row.keys():
                sys.exit(f"unexpected mapping row in {view['cdsName']}: {sorted(row.keys())}")
    return views


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
    parser.add_argument("--release", default="user's own system",
                        help="software release of the system the file came from, e.g. 'S4CORE 109 SP01'")
    args = parser.parse_args()

    views = load_views(args.file)
    if os.path.exists(TARGET):
        shutil.copyfile(TARGET, TARGET + ".bak")
    with open(TARGET, "w", encoding="utf-8", newline="\n") as f:
        json.dump(views, f, indent=2, ensure_ascii=False)
        f.write("\n")

    summary = summarize(views)
    version = {"source": "ZCDS_FIELD_MAPPING report, Download JSON",
               "release": args.release,
               "generated": datetime.date.today().isoformat(),
               **summary}
    with open(VERSION_FILE, "w", encoding="utf-8", newline="\n") as f:
        json.dump(version, f, indent=2)
        f.write("\n")
    print(json.dumps(summary, indent=2))


if __name__ == "__main__":
    main()
