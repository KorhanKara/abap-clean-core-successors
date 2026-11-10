#!/usr/bin/env python3
"""Regenerate src/zcl_cds_field_mapping_pairs.clas.abap from SAP's release info file.

Usage:
    python tools/update_pairs.py [--product pce|public] [--file local.json]
"""
import argparse
import json
import os
import urllib.request

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
TARGET = os.path.join(ROOT, "src", "zcl_cds_field_mapping_pairs.clas.abap")
BASE_URL = "https://raw.githubusercontent.com/SAP/abap-atc-cr-cv-s4hc/main/src/"
FILES = {"pce": "objectReleaseInfo_PCELatest.json", "public": "objectReleaseInfoLatest.json"}

CLASS = """CLASS zcl_cds_field_mapping_pairs DEFINITION
  PUBLIC FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES: BEGIN OF ts_pair,
             table_name TYPE string,
             cds_name   TYPE string,
             released   TYPE abap_bool,
           END OF ts_pair,
           tt_pair TYPE STANDARD TABLE OF ts_pair WITH EMPTY KEY.

    CLASS-METHODS get
      RETURNING VALUE(rt_pairs) TYPE tt_pair.
ENDCLASS.


CLASS zcl_cds_field_mapping_pairs IMPLEMENTATION.
  METHOD get.
    rt_pairs = VALUE #(
{rows} ).
  ENDMETHOD.
ENDCLASS.
"""


def load(product, path):
    if path:
        with open(path, encoding="utf-8") as f:
            return json.load(f)
    with urllib.request.urlopen(BASE_URL + FILES[product]) as response:
        return json.load(response)


def table_cds_pairs(entries):
    states = {(e["tadirObject"], e["tadirObjName"]): e.get("state") for e in entries}
    pairs = set()
    for entry in entries:
        if entry["tadirObject"] != "TABL":
            continue
        for successor in entry.get("successors") or []:
            if successor.get("tadirObject") == "DDLS":
                name = successor["tadirObjName"]
                pairs.add((entry["tadirObjName"], name, states.get(("DDLS", name)) == "released"))
    return sorted(pairs)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", choices=sorted(FILES), default="pce")
    parser.add_argument("--file", help="read a local copy instead of downloading")
    args = parser.parse_args()

    pairs = table_cds_pairs(load(args.product, args.file)["objectReleaseInfo"])
    rows = "\n".join(
        f"      ( table_name = `{table}` cds_name = `{cds}` released = {'abap_true' if released else 'abap_false'} )"
        for table, cds, released in pairs)
    with open(TARGET, "w", encoding="utf-8", newline="\n") as f:
        f.write(CLASS.format(rows=rows))
    print(f"{len(pairs)} pairs written to {TARGET}")


if __name__ == "__main__":
    main()
