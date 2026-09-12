#!/bin/bash
#
# CSV Toolkit — a whiptail-based interactive CSV explorer.
#
# Usage: ./main.sh <INPUT_FILE>
#
# Menu:
#   1) Show table size (rows x columns)
#   2) Find unique values in a column (+ optional export)
#   3) Sort the file by a chosen column (display or save)
#   4) Filter/extract rows by a condition (display or save)
#   5) Column statistics for a numeric column (min/max/sum/avg/count)
#   6) Search the whole file for a value (+ optional export)
#   *) Exit
#
# CSV quoting: fields are parsed with a small hand-rolled awk parser
# (see AWK_SPLITCSV below) so a quoted field ("like, this") is kept as
# one field even if it contains the delimiter, and "" inside a quoted
# field is unescaped to a literal ". This works with plain POSIX awk
# (mawk, busybox awk, gawk, ...) — it does not depend on gawk's FPAT.
# It is a best-effort parser, not a full RFC 4180 implementation: it
# assumes each record fits on one line (no embedded newlines).

set -u

INPUT_FILE=${1:-}

headers=()
delimiter_found=""
no_col=0
no_rw=0   # number of DATA rows (header excluded)

# ---------------------------------------------------------------------------
# Shared awk building block: quote-aware field splitter.
# splitcsv(str, result, delim) fills result[1..n] and returns n.
# ---------------------------------------------------------------------------
AWK_SPLITCSV='
function splitcsv(str, result, delim,    i, c, field, inquotes, n) {
  n = 0
  field = ""
  inquotes = 0
  for (i = 1; i <= length(str); i++) {
    c = substr(str, i, 1)
    if (inquotes) {
      if (c == "\"") {
        if (substr(str, i + 1, 1) == "\"") { field = field "\""; i++ }
        else inquotes = 0
      } else field = field c
    } else {
      if (c == "\"") inquotes = 1
      else if (c == delim) { result[++n] = field; field = "" }
      else field = field c
    }
  }
  result[++n] = field
  return n
}
'

# Re-quote a field for output if it contains the delimiter or a quote.
AWK_QUOTEFIELD='
function quotefield(v, delim,    q) {
  q = v
  if (index(q, "\"") > 0 || index(q, delim) > 0) {
    gsub(/"/, "\"\"", q)
    q = "\"" q "\""
  }
  return q
}
'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

error_box() {
  whiptail --title "Error" --msgbox "$1" 10 78
}

info_box() {
  whiptail --title "$1" --msgbox "$2" "${3:-15}" 78
}

# Print a single column (1-indexed) of the data rows (header skipped).
# $1 = column index
csv_get_column() {
  local col="$1"
  awk -v delim="$delimiter_found" -v col="$col" "$AWK_SPLITCSV"'
    NR > 1 {
      n = splitcsv($0, f, delim)
      if (col <= n) print f[col]
      else print ""
    }' "$INPUT_FILE"
}

# Print header + all data rows where a column matches a condition.
# $1 = column index, $2 = operator (eq|ne|contains|gt|lt|ge|le), $3 = value
csv_filter_rows() {
  local col="$1" op="$2" val="$3"
  awk -v delim="$delimiter_found" -v col="$col" -v op="$op" -v val="$val" \
    "$AWK_SPLITCSV$AWK_QUOTEFIELD"'
    NR == 1 { print; next }
    {
      n = splitcsv($0, f, delim)
      field = (col <= n) ? f[col] : ""
      keep = 0
      if      (op == "eq")       keep = (field == val)
      else if (op == "ne")       keep = (field != val)
      else if (op == "contains") keep = (index(field, val) > 0)
      else if (op == "gt")       keep = (field + 0 > val + 0)
      else if (op == "lt")       keep = (field + 0 < val + 0)
      else if (op == "ge")       keep = (field + 0 >= val + 0)
      else if (op == "le")       keep = (field + 0 <= val + 0)
      if (keep) {
        line = ""
        for (i = 1; i <= n; i++) {
          line = line quotefield(f[i], delim)
          if (i < n) line = line delim
        }
        print line
      }
    }' "$INPUT_FILE"
}

# Ask for an output filename, warn on overwrite, write $2 (content) to it.
save_to_file() {
  local prompt="$1" content="$2"
  local out
  out=$(whiptail --title "Save File" --inputbox "$prompt" 8 78 3>&1 1>&2 2>&3) || return 1
  [ -z "$out" ] && { error_box "No filename given. Nothing saved."; return 1; }

  if [ -e "$out" ]; then
    if ! whiptail --title "Overwrite?" --yesno "$out already exists. Overwrite it?" 8 78; then
      return 1
    fi
  fi

  if printf '%s\n' "$content" > "$out"; then
    info_box "File Saved" "Content saved to $out" 8
  else
    error_box "Could not write to $out. Check the path and permissions."
  fi
}

column_menu_options() {
  local opts=()
  for i in "${!headers[@]}"; do
    opts+=("$((i + 1))" "${headers[i]}")
  done
  printf '%s\n' "${opts[@]}"
}

# ---------------------------------------------------------------------------
# Setup: validate input, detect delimiter, read header
# ---------------------------------------------------------------------------

if [ -z "$INPUT_FILE" ]; then
  whiptail --title "Error" --msgbox "Usage error: no INPUT_FILE passed.\n\nUsage: $0 <file>" 10 78
  exit 1
fi

if [ ! -f "$INPUT_FILE" ]; then
  whiptail --title "Error" --msgbox "Error: no such file, or not a regular file: $INPUT_FILE" 8 78
  exit 1
fi

if [ ! -r "$INPUT_FILE" ]; then
  whiptail --title "Error" --msgbox "Error: file is not readable: $INPUT_FILE" 8 78
  exit 1
fi

if [ ! -s "$INPUT_FILE" ]; then
  whiptail --title "Error" --msgbox "Error: file is empty: $INPUT_FILE" 8 78
  exit 1
fi

detect_delimiter() {
  local delimiters=("," ";" "|" $'\t' " ")
  local first_line
  first_line=$(head -1 "$INPUT_FILE")

  for d in "${delimiters[@]}"; do
    if [[ "$first_line" == *"$d"* ]]; then
      delimiter_found="$d"
      break
    fi
  done

  if [ -z "$delimiter_found" ]; then
    whiptail --title "Error" --msgbox "Could not detect a delimiter on the header row. Please check the file format." 8 78
    return 1
  fi

  # Count DATA rows only (exclude header). NR-1 also tolerates a
  # missing trailing newline on the last line.
  no_rw=$(awk 'END{print NR-1}' "$INPUT_FILE")
  [ "$no_rw" -lt 0 ] 2>/dev/null && no_rw=0

  no_col=$(awk -v delim="$delimiter_found" "$AWK_SPLITCSV"'
    NR==1 { print splitcsv($0, f, delim); exit }' "$INPUT_FILE")

  if [ -z "$no_col" ] || [ "$no_col" -lt 1 ] 2>/dev/null; then
    whiptail --title "Error" --msgbox "Could not parse any columns from the header row." 8 78
    return 1
  fi

  return 0
}

find_header() {
  local line
  line=$(awk -v delim="$delimiter_found" "$AWK_SPLITCSV"'
    NR==1 {
      n = splitcsv($0, f, delim)
      out = ""
      for (i = 1; i <= n; i++) { out = out f[i]; if (i < n) out = out "\x1f" }
      print out
      exit
    }' "$INPUT_FILE")
  IFS=$'\x1f' read -r -a headers <<< "$line"
}

detect_delimiter || exit 1
find_header

if [ "${#headers[@]}" -eq 0 ]; then
  error_box "Header row could not be read. Aborting."
  exit 1
fi

# ---------------------------------------------------------------------------
# Main menu loop
# ---------------------------------------------------------------------------

while true; do
  choice=$(whiptail --title "CSV Toolkit — $(basename "$INPUT_FILE")" --menu "Choose an option" 25 78 16 \
    "1" "Show the size of the csv table." \
    "2" "Find the unique values in a column." \
    "3" "Sort the csv file based on a chosen column." \
    "4" "Filter and extract rows by a condition." \
    "5" "Column statistics (numeric)." \
    "6" "Search the whole file for a value." \
    "*" "Exit program." 3>&1 1>&2 2>&3)

  exitstatus=$?
  if [ $exitstatus != 0 ]; then
    break
  fi

  case "$choice" in
    '1')
      info_box "Table Size" "Data rows: $no_rw\nColumns:   $no_col\nDelimiter: '$delimiter_found'" 10
      ;;

    '2')
      col_choice=$(whiptail --title "Unique Values" --menu "Choose a column:" 25 78 16 \
        $(column_menu_options) 3>&1 1>&2 2>&3) || continue
      if [[ "$col_choice" =~ ^[0-9]+$ ]] && [ "$col_choice" -ge 1 ] && [ "$col_choice" -le "$no_col" ]; then
        unique_values=$(csv_get_column "$col_choice" | sort | uniq -c | sort -rn)
        if [ -z "$unique_values" ]; then
          error_box "No data found in that column."
        else
          if whiptail --title "Unique Values" --yes-button "Save to file" --no-button "Just show" \
              --yesno "Show the results, or save them to a file?" 8 78; then
            save_to_file "Enter the name of the output file:" "$unique_values"
          else
            whiptail --title "Unique Values (${headers[col_choice-1]})" --scrolltext --msgbox "$unique_values" 25 78
          fi
        fi
      fi
      ;;

    '3')
      col_choice=$(whiptail --title "Sort CSV" --menu "Choose a column:" 25 78 16 \
        $(column_menu_options) 3>&1 1>&2 2>&3) || continue
      if [[ "$col_choice" =~ ^[0-9]+$ ]]; then
        header=$(head -1 "$INPUT_FILE")
        sorted_content=$(tail -n +2 "$INPUT_FILE" | sort -t"$delimiter_found" -k"${col_choice},${col_choice}")
        display_or_save=$(whiptail --title "Sort Options" --menu "Choose an option" 25 78 16 \
          "d" "Display" "s" "Save to a file" 3>&1 1>&2 2>&3) || continue
        case "$display_or_save" in
          'd')
            { echo "$header"; echo "$sorted_content"; } | column -t -s"$delimiter_found" | less -S
            ;;
          's')
            save_to_file "Enter the name of the output file:" "$header
$sorted_content"
            ;;
        esac
      fi
      ;;

    '4')
      col_choice=$(whiptail --title "Filter Rows" --menu "Choose a column to filter on:" 25 78 16 \
        $(column_menu_options) 3>&1 1>&2 2>&3) || continue
      if [[ "$col_choice" =~ ^[0-9]+$ ]]; then
        op=$(whiptail --title "Condition" --menu "Choose a condition for ${headers[col_choice-1]}:" 25 78 16 \
          "eq" "equals" \
          "ne" "not equal to" \
          "contains" "contains substring" \
          "gt" "greater than (numeric)" \
          "ge" "greater than or equal (numeric)" \
          "lt" "less than (numeric)" \
          "le" "less than or equal (numeric)" \
          3>&1 1>&2 2>&3) || continue
        value=$(whiptail --title "Value" --inputbox "Value to compare against:" 8 78 3>&1 1>&2 2>&3) || continue

        filtered=$(csv_filter_rows "$col_choice" "$op" "$value")
        data_rows=$(echo "$filtered" | tail -n +2)
        if [ -z "$data_rows" ]; then
          match_count=0
        else
          match_count=$(echo "$data_rows" | wc -l)
        fi

        if [ "$match_count" -eq 0 ]; then
          error_box "No rows matched that condition."
        else
          display_or_save=$(whiptail --title "$match_count match(es)" --menu "Choose an option" 25 78 16 \
            "d" "Display" "s" "Save to a file" 3>&1 1>&2 2>&3) || continue
          case "$display_or_save" in
            'd')
              echo "$filtered" | column -t -s"$delimiter_found" | less -S
              ;;
            's')
              save_to_file "Enter the name of the output file:" "$filtered"
              ;;
          esac
        fi
      fi
      ;;

    '5')
      col_choice=$(whiptail --title "Column Statistics" --menu "Choose a numeric column:" 25 78 16 \
        $(column_menu_options) 3>&1 1>&2 2>&3) || continue
      if [[ "$col_choice" =~ ^[0-9]+$ ]]; then
        stats=$(csv_get_column "$col_choice" | awk '
          {
            if ($0 ~ /^-?[0-9]+([.][0-9]+)?$/) {
              n++; sum += $0
              if (n == 1 || $0 < min) min = $0
              if (n == 1 || $0 > max) max = $0
            } else if ($0 != "") {
              non_numeric++
            }
          }
          END {
            if (n == 0) {
              print "No numeric values found in this column."
            } else {
              printf "Count:    %d\n", n
              printf "Sum:      %s\n", sum
              printf "Average:  %.4f\n", sum / n
              printf "Min:      %s\n", min
              printf "Max:      %s\n", max
              if (non_numeric > 0) printf "\n(%d non-numeric/blank values were skipped)\n", non_numeric
            }
          }')
        info_box "Statistics: ${headers[col_choice-1]}" "$stats" 15
      fi
      ;;

    '6')
      search_term=$(whiptail --title "Search" --inputbox "Enter a value to search for (any column):" 8 78 3>&1 1>&2 2>&3) || continue
      if [ -n "$search_term" ]; then
        header=$(head -1 "$INPUT_FILE")
        matches=$(tail -n +2 "$INPUT_FILE" | grep -F -- "$search_term")
        if [ -z "$matches" ]; then
          match_count=0
        else
          match_count=$(echo "$matches" | wc -l)
        fi

        if [ "$match_count" -eq 0 ]; then
          error_box "No rows contain '$search_term'."
        else
          display_or_save=$(whiptail --title "$match_count match(es)" --menu "Choose an option" 25 78 16 \
            "d" "Display" "s" "Save to a file" 3>&1 1>&2 2>&3) || continue
          case "$display_or_save" in
            'd')
              { echo "$header"; echo "$matches"; } | column -t -s"$delimiter_found" | less -S
              ;;
            's')
              save_to_file "Enter the name of the output file:" "$header
$matches"
              ;;
          esac
        fi
      fi
      ;;

    *)
      break
      ;;
  esac
done

exit 0
