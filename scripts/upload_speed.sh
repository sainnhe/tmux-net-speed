#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/helpers.sh"

main()
{
    # TODO make configurable
    #local upload_file=$(get_tmux_option $UPLOAD_FILE)
    local file=$UPLOAD_FILE
    local vel=$(update_speed "$file" 9)

    ## Format output
    local format=$(get_tmux_option @upload_speed_format "%s")
    printf "$format" "$vel"
}
main

