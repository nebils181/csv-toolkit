# CSV Toolkit

A terminal-based, menu-driven CSV explorer built with `bash` and `whiptail`. Point it at any delimited file and interactively inspect, filter, sort, search, and summarize it — no spreadsheet app required.

## Features

- **Auto-detects the delimiter** — comma, semicolon, pipe, tab, or space
- **Quoted-field aware** — `"Doe, John"` is treated as one field even with a comma inside; `""` escaping is handled
- **Table size** — row and column counts at a glance
- **Unique values** — frequency count for any column, viewable or exportable
- **Sort** — sort by any column, view in a pager or save to a new file
- **Filter/extract** — keep rows matching a condition (`=`, `≠`, `contains`, `>`, `>=`, `<`, `<=`) and view or save the results
- **Column statistics** — count, sum, average, min, and max for a numeric column
- **Search** — grep any value across the entire file
- Built on plain POSIX `awk` (works with `mawk`, the Debian/Ubuntu default — no `gawk` dependency)

## Requirements

- `bash`
- [`whiptail`](https://en.wikipedia.org/wiki/Newt_(programming_library)) (usually preinstalled on Debian/Ubuntu; `sudo apt install whiptail` otherwise)
- `awk`, `sort`, `grep`, `column`, `less` (standard on virtually any Linux system)

## Usage

```bash
chmod +x main.sh
./main.sh path/to/file.csv
```

You'll land in a menu:

```
1) Show the size of the csv table.
2) Find the unique values in a column.
3) Sort the csv file based on a chosen column.
4) Filter and extract rows by a condition.
5) Column statistics (numeric).
6) Search the whole file for a value.
*) Exit program.
```

Pick a number, follow the prompts, and choose to **display** results in a pager or **save** them to a new file.

## Example

```bash
./main.sh sample_data/username.csv
```

- Menu **2** on the `city` column shows how many rows fall in each city.
- Menu **4** on `age` with condition `>` and value `30` extracts everyone over 30.
- Menu **5** on `age` prints count/sum/average/min/max for the column.

## Limitations

- Assumes each CSV record fits on a single line (no embedded newlines inside quoted fields).
- This is a best-effort quoted-CSV parser, not a full RFC 4180 implementation.
- Column-based operations (filter, stats, unique values) work on one column at a time via the menu — there's no multi-column query language.
