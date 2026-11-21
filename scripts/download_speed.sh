#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "$CURRENT_DIR/helpers.sh"

main()
{
    # TODO make configurable
    #local file=$(get_tmux_option $DOWNLOAD_FILE)
    local file=$DOWNLOAD_FILE
    local vel=$(update_speed "$file" 1)

    ## Format output
    local format=$(get_tmux_option @download_speed_format "%s")
    printf "$format" "$vel"
}
main

