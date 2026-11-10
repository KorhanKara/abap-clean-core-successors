# ABAP table field to CDS field mapping

Enter a classic table, get the field-level mapping to its released successor CDS views, read from the dictionary of your own system.

SAP's [Cloudification Repository](https://github.com/SAP/abap-atc-cr-cv-s4hc) tells you that `MARA` is replaced by `I_Product`. It does not tell you which `I_Product` field replaces `MARA-MATKL`. That is the question you have on every `SELECT` you migrate to clean core, and this report answers it.

| Table | Table field | CDS view | CDS field |
|---|---|---|---|
| `MARA` | `MATKL` | `I_PRODUCT` | `ProductGroup` |
| `MARA` | `MTART` | `I_PRODUCT` | `ProductType` |
| `VBAK` | `AUART` | `I_SALESDOCUMENT` | `SalesDocumentType` |

## Why read it from the system

A shared mapping file is correct for one release. The report reads the system it runs on, so the result matches the views you actually have, including their field names and any fields your release does not have yet.

It only reads. It writes nothing to the database and opens no outbound connection.

## Install

Two ways, same code:

- **abapGit:** pull this repository into a local or Z package. It creates the report `ZCDS_FIELD_MAPPING` and the classes `ZCL_CDS_FIELD_MAPPING` and `ZCL_CDS_FIELD_MAPPING_PAIRS`.
- **Copy and paste:** create an executable report in SE38, for example `ZCDS_FIELD_MAPPING`, paste [standalone/zcds_field_mapping.abap](standalone/zcds_field_mapping.abap) over its source and activate. Everything is in that one source as local classes, selection texts included.

No other dependency is needed.

## Use

Run `ZCDS_FIELD_MAPPING` in SE38.

| Input | Meaning |
|---|---|
| Table | Table to look up. Empty means all tables in the list. Only on screen. |
| Table fields | One or more fields of the table, for example the ones your `SELECT` reads. The views covering the most of them come first, and the list header says whether a single view covers them all. A field no listed view covers appears with an empty view. Needs a table. Only on screen. |
| CDS view | Use this view instead of SAP's list. Works for any table and view pair, including your own views. Needs a table. Only on screen. |
| Show on screen | ALV list. Use its standard export for a spreadsheet. |
| Download JSON | Write the mapping of all tables to a file, for scripts, CI or AI assistants. The other inputs are hidden, and the report asks for the file when you run it. The file also holds view fields that could not be traced to a column, with an empty `tableField`. |

Click a table or CDS view in the list to see its key fields in a pop-up. Use them to write the join conditions when one view is not enough.

The Match column tells you how far to trust a row:

- **Same column**: the view field reads this column.
- **In expression**: the view field uses this column inside an expression, so the value can differ. In `I_PRODUCT`, `LastChangedByUser` returns `MARA-AENAM`, or `ERNAM` when `AENAM` is empty. Click **Show** in the How to use column to see the definition. In JSON these rows carry `"computed": true`, the `expression` and the view it is `definedIn`.

The Release column appears only when a listed view is not released. SAP can name such a view as a successor: `EHEWAD_WA_TRRQLA` points to `I_WASTETRANSFERREQUESTHISTORY`, and reading that view gives the ATC finding "Usage of internal API". A view you enter yourself is not checked.

## Use with an AI assistant

`skill/cds-field-mapping` is an agent skill that answers the same question in chat: ask "what do I use instead of `MARA-MATNR`?" and it looks the field up instead of guessing a name. It can also rewrite a simple `SELECT` on a classic table into one on the released view, with every renamed field aliased to its old name.

It ships with the mapping of 294 pairs read from an S4CORE 109 SP01 system, standard fields only, so it works without an SAP connection. To use your own release and your own extension fields, run the report with Download JSON and load the file:

```bash
python3 skill/cds-field-mapping/scripts/import_mapping.py core-data-services.json
```

Copy the `skill/cds-field-mapping` folder to wherever your assistant loads skills from, for example `~/.claude/skills/` for Claude Code. The scripts need Python 3 and nothing else.

## How it works

1. `ZCL_CDS_FIELD_MAPPING_PAIRS` holds the table to CDS pairs from SAP's `objectReleaseInfo_PCELatest.json`.
2. For a view with a generated SQL view, the field-to-column resolution comes from `DD27S`, the dictionary's own record. Intermediate views are followed level by level, up to 10 levels. All branches of a `UNION` are tried.
3. Computed fields and type-changing `CAST`s point at helper tables in `DD27S`. These are resolved from the view definition and confirmed against `DD03L`, or against the source view when the source is a view.
4. View entities have no SQL view, so their definition is parsed through the XCO library, falling back to the DDL source.

## Limits

- A field stays unmapped when its definition names no column of the table: literals, association paths, or a read from a different table. An empty result for a listed pair can be correct.
- A computed field can list several columns, one row each. The list says which columns it reads, not how it combines them.
- A mapping means the view field reads that column. It does not prove that the view returns the same rows. Check the view's joins and filters before you replace a `SELECT`.
- A pair is shown only if SAP's list names it. Use the CDS view input for anything else.
- The report reads your own system, so fields added to a view by your extensions or add-ons are listed too.
- Reading `DD27S` needs classic ABAP. The report does not run in ABAP Cloud, on BTP or in a public cloud tenant.

## Results and tested releases

| Release | Result |
|---|---|
| S4CORE 109 SP01, SAP_BASIS 816 | Full run: 294 pairs, 234 views, 10,004 standard CDS fields. 7,358 read one column, 280 use columns in an expression. |
| SAP_BASIS 755 | The copy-and-paste source of the current build compiles and activates. Not run. |

The class uses XCO, so releases older than the ones above may not compile.

## Update the pair list

```bash
python tools/update_pairs.py
```

This downloads SAP's latest file, regenerates the class and rebuilds the copy-and-paste source. Use `--product public` for the public cloud list, or `--file` for a local copy. After changing anything in `src/`, run `python tools/build_standalone.py` so the two stay the same.

## License

MIT. The pair list is derived from [SAP/abap-atc-cr-cv-s4hc](https://github.com/SAP/abap-atc-cr-cv-s4hc), which is licensed under Apache-2.0.

This is an independent project and is not affiliated with or endorsed by SAP.
