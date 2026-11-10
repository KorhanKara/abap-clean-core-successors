#!/usr/bin/env python3
"""Regenerate src/zcl_cds_field_mapping_pairs.clas.abap from SAP's release info file.

Usage:
    python tools/update_pairs.py [--product pce|public] [--file local.json]
"""
import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import build_standalone  # noqa: E402

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir))
TARGET = os.path.join(ROOT, "src", "zcl_cds_field_mapping_pairs.clas.abap")
SKILL_SUCCESSORS = os.path.join(ROOT, "skill", "cds-field-mapping", "references", "successors.json")
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


STATES = {"released": "RELEASED", "deprecated": "DEPRECATED",
          "notToBeReleased": "NOT_TO_BE_RELEASED", "notToBeReleasedStable": "NOT_TO_BE_RELEASED_STABLE"}


def display_type(item):
    return item["tadirObject"] if item.get("objectType") in (None, "CDS_STOB") else item["objectType"]


def skill_successors(entries):
    """Successor rows in the format of the report's Download JSON, for the skill's bundled data."""
    states = {(display_type(e), e["objectKey"]): e.get("state") for e in entries}
    rows = []
    for entry in entries:
        for successor in entry.get("successors") or []:
            state = states.get((display_type(successor), successor["objectKey"]))
            rows.append({"objectType": display_type(entry),
                         "objectName": entry["objectKey"],
                         "objectState": STATES.get(entry.get("state"), "NO ENTRY"),
                         "successorType": display_type(successor),
                         "successorName": successor["objectKey"],
                         "abapCloud": "Released" if state == "released" else "Not released"})
    return sorted(rows, key=lambda r: (r["objectType"], r["objectName"], r["successorName"]))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--product", choices=sorted(FILES), default="pce")
    parser.add_argument("--file", help="read a local copy instead of downloading")
    args = parser.parse_args()

    entries = load(args.product, args.file)["objectReleaseInfo"]
    successors = skill_successors(entries)
    with open(SKILL_SUCCESSORS, "w", encoding="utf-8", newline="\n") as f:
        json.dump(successors, f, indent=2)
        f.write("\n")
    print(f"{len(successors)} successors written to {SKILL_SUCCESSORS}")

    pairs = table_cds_pairs(entries)
    rows = "\n".join(
        f"      ( table_name = `{table}` cds_name = `{cds}` released = {'abap_true' if released else 'abap_false'} )"
        for table, cds, released in pairs)
    with open(TARGET, "w", encoding="utf-8", newline="\n") as f:
        f.write(CLASS.format(rows=rows))
    print(f"{len(pairs)} pairs written to {TARGET}")
    build_standalone.build()


if __name__ == "__main__":
    main()
