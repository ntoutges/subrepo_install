#!/usr/bin/env bash

MOD_FILE=".srimodules"

# Search for .git file/dir indicating root of some repo
while ! ([ -f .git ] || [ -d .git ]); do

    # Found root directory; Give up!
    if [ "$PWD" == "/" ]; then
        echo "Unable to locate '.git' file/directory"
        exit 1
    fi

    cd .. # Move to parent dir
done

echo "Installing modules in '$PWD'..."

# Search for file containing all submodule information

if ! [ -f "$MOD_FILE" ]; then
    echo "No '$MOD_FILE' file found"
    exit 1
fi

# Read through submodule file
linenum=0
while read line; do

    linenum=$((linenum + 1))

    # Ignore comments
    line=$(sed "s/#.*//" <<< "$line")

    # Skip empty lines
    if ! (grep -qE "\S" <<< "$line"); then
        continue
    fi

    # Split by spaces to get 3 parts
    # Format: [URL][?location][?commit]
    parts=($line)

    if (( ${#parts[@]} > 4 )); then
        echo "Unrecognized arguments on line $linenum"
        continue # Avoid installing line that we don't understand
    fi

    # Install entry
    if [ "${#parts[@]}" -eq 1 ]; then # Install in default location
        git clone "${parts[0]}"
    elif [ "${#parts[@]}" -eq 2 ]; then # Install in specified location
        git clone "${parts[0]}" "${parts[1]}"
    else # Install in a specified location from some commit id
        git clone "${parts[0]}" "${parts[1]}"
        (
            cd "${parts[1]}"

            # Attempt to checkout branch
            # If not a branch, treat as commit id
            git checkout "${parts[2]}" || git switch --detach "${parts[2]}"
        )
    fi

done <"$MOD_FILE"


# $FILE=(ls | grep -E "^.srimodules$")
