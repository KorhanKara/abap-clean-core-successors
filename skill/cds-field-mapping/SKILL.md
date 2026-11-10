---
name: cds-field-mapping
description: Answer which released CDS view field replaces a classic SAP table field (MARA-MATNR to I_PRODUCT-Product), what replaces another SAP object such as a function module, class or old CDS view, and rewrite simple SELECTs from a classic table to a released CDS view, from data read out of a real SAP system. Use whenever the user asks what to use instead of a table, table field, function module, BAPI, class or data element, which CDS view replaces a table, how to migrate a SELECT to a released API or clean core, or shares a SELECT on a classic table. Also use to load the user's own file downloaded from the ZCDS_FIELD_MAPPING report.
---

# CDS field mapping

The user wants to stop reading a classic table and read a released CDS view
instead. SAP publishes which view replaces which table. This skill answers the
part SAP does not publish: which view field replaces which table field.

Answer from the data, never from memory. CDS field names look guessable and are
not: `MARA-MATKL` is `ProductGroup`, not `MaterialGroup`.

## Look it up

Run the scripts from this skill's folder. Use `python3`, or `py -3` on Windows.

```bash
python3 scripts/cds_field_mapping.py --table MARA --field MATNR   # which view field replaces this field
python3 scripts/cds_field_mapping.py --table MARA                 # all views and their full mapping
python3 scripts/cds_field_mapping.py --cds I_PRODUCT --field ProductGroup   # where a view field comes from
python3 scripts/cds_field_mapping.py --rewrite "SELECT SINGLE matnr matkl FROM mara INTO @DATA(ls_mara) WHERE matnr = @lv_matnr."
python3 scripts/cds_field_mapping.py --object BAPI_PROCORD_GET_DETAIL   # successor of any object, * as wildcard
python3 scripts/cds_field_mapping.py --object I_STOCK* --type DDLS
```

Not-released views are skipped. Add `--allow-unreleased` only to explain why a
view SAP names is not usable.

## How to answer

- **Several views can cover one field.** `MARA-MATNR` is `Product` in five views.
  Prefer the view that covers every field the user's `SELECT` reads, so the
  statement keeps one source. `--rewrite` sorts candidates by fewest
  `unmappedFields`. For a single field the data gives no ranking: list the views
  and ask which other fields the user reads, instead of picking one from memory.
- **`computed: true` in a `--cds --field` answer** means the view field has no
  single column: `readsColumns` and `expression` say what it is built from.
- **Alias every renamed field** as `CdsField AS original_field`. The rest of the
  program still uses the old names, and the alias keeps the change to one
  statement. `--rewrite` already does this; do the same in any rewrite you write
  by hand (joins, subqueries, `FOR ALL ENTRIES`).
- **Report unmapped fields, never drop them.** A field missing from a view means
  that view is the wrong target or the rewrite needs a join. Dropping it gives code
  that compiles and returns wrong data.
- **`usedInExpression` is information, not a replacement.** It lists view fields
  that use the column inside a `CASE`, a calculation or a function, with the
  definition. The value can differ from the column, so do not alias the view field
  to the column. Show the expression and let the user decide.
- **An empty mapping can be correct.** A view SAP names as successor can read a
  different table or take a field through an association.
- **A mapping is not proof of the same rows.** The view can filter or join.
  Present rewrites as drafts to compile and test, and name the release the data
  was read from (`dataRelease` in the output) when it matters.
- **`abapCloud` decides whether a successor helps.** `Released` clears the ATC
  finding "Usage of APIs". `Key user only` is released for key user apps but not
  for ABAP Cloud, so ATC still reports it as an internal API; say so instead of
  recommending it. `Not released` is not usable either.
- **A function module has no field mapping.** For `--object` results, give the
  successor and its type; for a CDS successor of a table, continue with `--table`.
- **No row for an object means SAP's list names no successor.** It does not mean
  the object is safe to use. Say what the data shows and do not invent a successor.

## The data

`references/core-data-services.json` holds one entry per table and view pair:
`tableName`, `cdsName`, `released` and a `mapping` list. Each row has `cdsField`
and `tableField`. Rows with `computed: true` also carry `expression` and
`definedIn`: the view field reads that column inside an expression. A row with an
empty `tableField` could not be traced to a column of the table.

`references/successors.json` holds one row per object and successor:
`objectType`, `objectName`, `objectState`, `successorType`, `successorName` and
`abapCloud`. Function modules appear under their own name.

`references/DATA_VERSION.json` records where each file came from. Both bundled
files are read from a standard S/4HANA 2025 system (`S4CORE 109 SP1`) with add-on
and customer fields removed. Other releases can have other fields and other
successors; the user's own file settles that.

## Use the user's own system

When the user's release differs, or they want their own extension fields, they
can load their own data:

1. Install the `ZCDS_FIELD_MAPPING` report from this repository, with abapGit or
   by pasting `standalone/zcds_field_mapping.abap` into a new report.
2. Run it with **Download JSON**. The report asks where to save the file; any
   folder works.
3. Run `python3 scripts/import_mapping.py <path to the file>` from this skill's
   folder, the copy the assistant loads. The file carries its release;
   `--release` only overrides it.

The one file holds both the mapping and the successor list. The import replaces
both bundled files and keeps the old ones with a `.bak` suffix. On S/4HANA 2020 the
report has no successor list to download, so the bundled one stays. The new files
can hold the user's own fields, so they stay on their machine.

Creating objects in an SAP system is the user's decision. Do not install or run
the report for them without asking.
