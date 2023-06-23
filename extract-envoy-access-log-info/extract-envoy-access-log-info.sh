#!/bin/bash

# Read a line from a file
read -r line < input.txt

# Remove leading and trailing spaces from the line
line="${line#"${line%%[![:space:]]*}"}"
line="${line%"${line##*[![:space:]]}"}"

# Set the delimiter to space
IFS=' ' read -ra units <<<"$line"

# Initialize variables
in_quote=false

# Loop through the units
for unit in "${units[@]}"; do
    if [[ $unit == \"* && $unit != *\" ]]; then
        # Found the start of a quoted sequence
        in_quote=true
        extracted_unit="$unit"
    elif [[ $unit == *\" ]]; then
        # Found the end of a quoted sequence
        in_quote=false
        extracted_unit+=" $unit"
        echo "$extracted_unit"
        extracted_unit=""
    elif [ "$in_quote" = true ]; then
        # Inside a quoted sequence
        extracted_unit+=" $unit"
    else
        # Outside a quoted sequence
        echo "$unit"
    fi
done
