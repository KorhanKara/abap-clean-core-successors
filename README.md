# ABAP clean core successors

Find the released successor of a classic SAP object, down to the field, read from your own system: which released CDS view field replaces a table field, and what replaces a function module, class, data element, domain or older CDS view. Each successor shows whether it clears the ATC finding "Usage of APIs". It comes as an ABAP report and as an AI agent skill.

SAP's [Cloudification Repository](https://github.com/SAP/abap-atc-cr-cv-s4hc) tells you that `MARA` is replaced by `I_Product`. It does not tell you which `I_Product` field replaces `MARA-MATKL`. That is the question you have on every `SELECT` you migrate to clean core, and this report answers it.

| Table | Table field | CDS view | CDS field |
|---|---|---|---|
| `MARA` | `MATKL` | `I_PRODUCT` | `ProductGroup` |
| `MARA` | `MTART` | `I_PRODUCT` | `ProductType` |
| `VBAK` | `AUART` | `I_SALESDOCUMENT` | `SalesDocumentType` |

## Why read it from the system

A shared mapping file is correct for one release. The report reads the system it runs on, so the result matches the views you actually have, including their field names and any fields your release does not have yet.

It only reads. It writes nothing to the database and opens no outbound connection.

## Which system you need

The report reads SAP's own successor list from the system (`ARS_W_API_SCCSSR` and `ARS_W_API_STATE`, contract C1). This is the same data the ATC check "Usage of APIs" reads with `releasedAPIDataSource = checkedSystem`, so the report and ATC give the same answer. SAP fills this list from **S/4HANA 2022** on.

- **S/4HANA 2022 or later:** use the report. It answers for your release and your own extension fields.
- **Older releases:** the list is empty, so the system has no reliable answer to read, and the report stops with a message. Use the [AI skill](#use-with-an-ai-assistant) instead. It ships with data from an S/4HANA 2025 FPS01 system, so a view or field it names may not exist in your release yet; check it in your system before you use it.

The report does not carry a list of its own on purpose: a built-in list would hold SAP's latest successors, not the ones of your release, and would look more certain than it is.

Tested on S/4HANA 2025 FPS01 (`S4CORE 109 SP1`). On S/4HANA 2022 the successor list was checked in the database, but the report has not been run there yet.

## Install

Two ways, same code:

- **abapGit:** pull this repository into a local or Z package. It creates the report `ZCLEAN_CORE_SUCCESSORS` and the class `ZCL_CLEAN_CORE_SUCCESSORS`.
- **Copy and paste:** create an executable report in SE38, for example `ZCLEAN_CORE_SUCCESSORS`, paste [standalone/zclean_core_successors.abap](standalone/zclean_core_successors.abap) over its source and activate. Everything is in that one source as local classes, selection texts included.

No other dependency is needed.

## Use

Run `ZCLEAN_CORE_SUCCESSORS` in SE38. Execute (F8) shows a list on screen; the **Download JSON** button in the toolbar writes everything to one file.

Pick what to look up on screen:

- **Table fields to CDS**: the field-level mapping of a classic table to its successor views.
- **Other objects**: the successor of any object SAP has replaced, for example a function module, class, data element or older CDS view.

**Download JSON** ignores the inputs on the screen and writes everything to one file, for scripts, CI or AI assistants:

```json
{
  "release": "S4CORE 109 SP1",
  "pairsFrom": "this system",
  "tables": [ { "cdsName": "I_PRODUCT", "tableName": "MARA", "released": true, "mapping": [ ... ] } ],
  "successors": [ { "objectType": "FUNC", "objectName": "BAPI_PROCORD_GET_DETAIL", "objectState": "NOT_TO_BE_RELEASED",
                    "successorType": "DDLS", "successorName": "I_MANUFACTURINGORDER", "abapCloud": "Released" } ]
}
```

`tables` holds the mapping of every table in the list, including view fields that could not be traced to a column (empty `tableField`). `successors` holds every successor in the system.

### Table fields to CDS

| Input | Meaning |
|---|---|
| Table | Table to look up. Empty means all tables in the list. Only on screen. |
| Table fields | One or more fields of the table, for example the ones your `SELECT` reads. The views covering the most of them come first, and the list header says whether a single view covers them all. A field no listed view covers appears with an empty view. Needs a table. Only on screen. |
| CDS view | Use this view instead of SAP's list. Works for any table and view pair, including your own views. Needs a table. |

The list is an ALV; use its standard export for a spreadsheet.

Click a table or CDS view in the list to see its key fields in a pop-up. Use them to write the join conditions when one view is not enough.

The Match column tells you how far to trust a row:

- **Same column**: the view field reads this column.
- **In expression**: the view field uses this column inside an expression, so the value can differ. In `I_PRODUCT`, `LastChangedByUser` returns `MARA-AENAM`, or `ERNAM` when `AENAM` is empty. Click **Show** in the How to use column to see the definition. In JSON these rows carry `"computed": true`, the `expression` and the view it is `definedIn`.

The list only shows views released for ABAP Cloud, because only those clear the ATC finding. SAP can name a view that is not: `EHEWAD_WA_TRRQLA` points to `I_WASTETRANSFERREQUESTHISTORY`, and reading that view gives the ATC finding "Usage of internal API". The report leaves such a view out and tells you so when it is the only successor. A view you enter yourself is checked the same way.

### Other objects

| Input | Meaning |
|---|---|
| Object name | Name of the object, with `*` as a wildcard. For a function module, give the function module, not its group. Empty lists every successor, or every successor of the object type you choose. |
| Object type | Optional filter, for example `FUNC`, `CLAS`, `INTF`, `DTEL`, `DDLS`, `TABL`. Press F4 for the types that have successors in your system. |

The list shows the object and its type with a short text, its state and its successor. It only lists successors released for ABAP Cloud, because only those clear the ATC finding "Usage of APIs".

SAP also names successors that do not: some are released for key user apps only, a few are not released at all. On an S/4HANA 2025 system `I_EWM_STORAGETYPE_2`, SAP's successor of `I_EWM_STORAGETYPE`, is released for key user apps only, and reading it still gives "Usage of internal API". The report leaves these out of the list; when such a successor is the only one, it tells you which one and why it does not help. The JSON file and the AI skill keep them, marked with `abapCloud`, so you can still see what SAP named.

When an object has no successor, the report says whether it is already released for ABAP Cloud or simply has no successor in SAP's list.

### Where the successor list comes from

Both modes read SAP's own successor and API state lists in the system (`ARS_W_API_SCCSSR`, `ARS_W_API_STATE`), contract C1. A successor counts as released only when SAP marks it for use in ABAP Cloud development, the same rule the ATC check applies. See [Which system you need](#which-system-you-need).

## Use with an AI assistant

`skill/clean-core-successors` is an agent skill that answers the same questions in chat: ask "what do I use instead of `MARA-MATNR`?" or "what replaces `BAPI_PROCORD_GET_DETAIL`?" and it looks the answer up instead of guessing a name. It can also rewrite a simple `SELECT` on a classic table into one on the released view, with every renamed field aliased to its old name.

### Install the skill

Copy the `skill/clean-core-successors` folder to wherever your assistant loads skills from, for example `~/.claude/skills/clean-core-successors` for Claude Code. The scripts need Python 3 and nothing else.

### Data included in the repository

The skill ships with data read from an **S/4HANA 2025 FPS01** system (`S4CORE 109 SP1`): the field mapping of 294 table to CDS pairs and 1,090 successors, standard SAP objects and fields only. It works with this data as it is, without an SAP connection and without running the report.

### Update it to your own system

Your release can have other views, other fields and other successors, and your system has its own extension fields. To make the skill answer for your system:

1. Run `ZCLEAN_CORE_SUCCESSORS` in SE38 and press **Download JSON** in the toolbar.
2. The report asks where to save the file. Any folder on your PC works, for example `C:\Users\<you>\Downloads\clean-core-successors.json`.
3. Load the file into the copy of the skill your assistant uses. With the install path above:

   ```bash
   python3 ~/.claude/skills/clean-core-successors/scripts/import_mapping.py "C:\Users\<you>\Downloads\clean-core-successors.json"
   ```

   On Windows, `py -3` works in place of `python3`.

The import copies the data into the skill's `references` folder, keeps the previous files with a `.bak` suffix and records the release from the file. The downloaded file is not needed afterwards. Because it can hold your own extension fields, keep it and the updated skill to yourself.

On releases before S/4HANA 2022 the report does not run, so the skill's bundled S/4HANA 2025 data is what you work with. See [Which system you need](#which-system-you-need).

## How it works

1. The table to CDS pairs come from the system's successor list.
2. For a view with a generated SQL view, the field-to-column resolution comes from `DD27S`, the dictionary's own record. Intermediate views are followed level by level, up to 10 levels. All branches of a `UNION` are tried.
3. Computed fields and type-changing `CAST`s point at helper tables in `DD27S`. These are resolved from the view definition and confirmed against `DD03L`, or against the source view when the source is a view.
4. View entities have no SQL view, so their definition is parsed through the XCO library, falling back to the DDL source.

## Limits

- A field stays unmapped when its definition names no column of the table: literals, association paths, or a read from a different table. An empty result for a listed pair can be correct.
- A computed field can list several columns, one row each. The list says which columns it reads, not how it combines them.
- A mapping means the view field reads that column. It does not prove that the view returns the same rows. Check the view's joins and filters before you replace a `SELECT`.
- A pair is shown only if SAP's list names it. Use the CDS view input for anything else.
- The report needs S/4HANA 2022 or later; see [Which system you need](#which-system-you-need).
- Function modules are listed by their own name; SAP stores them under the function group.
- The report reads your own system, so fields added to a view by your extensions or add-ons are listed too.
- Reading `DD27S` needs classic ABAP. The report does not run in ABAP Cloud, on BTP or in a public cloud tenant.

## Development

`standalone/zclean_core_successors.abap` is generated from `src/`. After changing anything in `src/`, run `python tools/build_standalone.py` so the two stay the same.

## License

MIT. SAP publishes the same successor lists in [SAP/abap-atc-cr-cv-s4hc](https://github.com/SAP/abap-atc-cr-cv-s4hc) under Apache-2.0.

This is an independent project and is not affiliated with or endorsed by SAP.
