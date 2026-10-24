#!/usr/bin/env bash

MOD_FILE=".srimodules"
LOG_FILE=".logs.tmp" # Temporary logs file

# Search for .git file/dir indicating root of some repo
while ! ([ -f .git ] || [ -d .git ]); do

    # Found root directory; Give up!
    if [ "$PWD" == "/" ]; then
        echo "Unable to locate '.git' file/directory"
        exit 1
    fi

    cd .. # Move to parent dir
done

# Search for file containing all submodule information
if ! [ -f "$MOD_FILE" ]; then
    echo "No '$MOD_FILE' file found"
    exit 1
fi

print_error() {
    echo -ne "\e[0;31m" # Indicate error; red text
    cat "$LOG_FILE" # Dump logs to terminal for diagnosis
    echo -ne "\e[0m" # Revert to standard colors
}

mod_files=("$PWD/$MOD_FILE") # Stack of MOD_FILE files that still need to be installed

# Get absolute path for log file
LOG_FILE=$(realpath "$LOG_FILE")

install() {

    local filename="$1"
    local filepath=$(sed -E "s/^(.*\/)[^/]*$/\1/" <<< "$filename")
    local update_gitignore="$2"

    echo "Installing modules in $filepath"

    # Read through submodule file
    local linenum=0
    local action=0
    while read line; do

        linenum=$((linenum + 1))

        # Ignore comments
        local line=$(sed "s/#.*//" <<< "$line")

        # Skip empty lines
        if ! (grep -qE "\S" <<< "$line"); then
            continue
        fi

        # Split by spaces to get 3 parts
        # Format: [URL][?location][?commit]
        local parts=($line)

        if (( ${#parts[@]} > 4 )); then
            echo " Unrecognized arguments on line $linenum"
            continue # Avoid installing line that we don't understand
        fi

        action=1 # Mark that something actually happened

        local path="$filepath" # Set filepath as root
        local commit

        # Extract path data
        if [ "${#parts[@]}" -eq 1 ]; then # Using default location
            path+=$(sed -E "s/^.*\/([^\/]*)\.[^.]*$/\1/" <<< "${parts[0]}")
        else # Using provided location
            path+="${parts[1]}"
        fi

        # Extract commit/branch data
        if [ "${#parts[@]}" -eq 3 ]; then # Using default branch
            commit=""
        else # Use provided commit/branch
            commit="${parts[2]}"
        fi

        # Entry not yet installed
        if [ ! -d "$path" ]; then

            echo -n " Cloning ${parts[0]} ... "

            # Install entry
            git clone "${parts[0]}" "$path" &> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                echo "Failed to clone"
                print_error
                continue
            fi

            # Move to specified commit if required
            if [ ! -z "$commit" ]; then (
                cd "$path"

                # Attempt to checkout branch
                # If not a branch, treat as commit id
                git checkout "$commit" &> "$LOG_FILE" || git switch --detach "$commit" &> "$LOG_FILE"

                # Failed to clone properly
                if [ $? -ne 0 ]; then
                    echo "Failed to checkout"
                    print_error
                    continue
                fi

            ) fi

            (
                cd "$path"

                # Install git submodules (backwards-compatibility)
                git submodule update --init --recursive &> "$LOG_FILE"
                if [ $? -ne 0 ]; then
                    echo "Failed to install git submodules"
                    print_error
                    continue
                fi
            )

            echo "Success!"

            # Ensure git doesn't track these new files
            relpath="/$(realpath --relative-to "$PWD" "$path")"
            if [ ! -f ".gitignore" ] || ! grep -qxF "$relpath" ".gitignore"; then
                echo "$relpath" >> .gitignore
            fi

        else (
            echo -n " Updating $path ... "

            # Move into git repo
            cd "$path"

            # Revert any local changes
            git reset --hard HEAD &> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                echo "Failed to reset"
                print_error
                continue
            fi

            # Fetch any remote changes
            git fetch &> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                echo "Failed to reset"
                print_error
                continue
            fi

            if [ -z "$commit" ]; then # No commit specified

                # Move to default branch
                git checkout main &> "$LOG_FILE"
                if [ $? -ne 0 ]; then
                    echo "Failed to checkout main"
                    print_error
                    continue
                fi
            else # Commit/branch specified

                # Attempt to checkout branch
                # If not a branch, treat as commit id
                git checkout "$commit" &> "$LOG_FILE" || git switch --detach "$commit" &> "$LOG_FILE"
                if [ $? -ne 0 ]; then
                    echo "Failed to checkout $commit"
                    print_error
                    continue
                fi
            fi

            # Fetch+merge any changes
            git pull &> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                echo "Failed to pull"
                print_error
                continue
            fi

            # Install git submodules (backwards-compatibility)
            git submodule update --init --recursive &> "$LOG_FILE"
            if [ $? -ne 0 ]; then
                echo "Failed to install git submodules"
                print_error
                continue
            fi

            echo "Success!"

        ) fi

        # Search for sub-install scripts
        while read nested_path; do
            
            # User feedback
            echo -ne "\e[0;32m" # Set color to green
            echo " + $nested_path"
            echo -ne "\e[0m" # Revert to standard colors

            # Push to stack to run install script on these later modules
            mod_files+=("$nested_path")

        done < <(find "$path" -type f -name ".srimodules")

    done <"$filename"

    if [ "$action" -eq 0 ]; then
        echo " Empty..."
    fi
}

update_gitignore=1

while [ "${#mod_files[@]}" -ne 0 ]; do

    # Pop file from stack
    mod_file="${mod_files[-1]}"
    unset "mod_files[-1]"

    # Install file
    install "$mod_file" "$update_gitignore"
    update_gitignore=0

done

# Remove temporary file
if [ -f "$LOG_FILE" ]; then
    rm "$LOG_FILE"
fi
