set -eu

: "${FILE:=/dev/stdin}"  # Path to the file to append to the report, or read from standard input
: "${TITLE:=}"           # Message to print above the report
: "${LANGUAGE:=}"        # Language to use for syntax highlighting when printing the file contents in a code block
: "${CODE_BLOCK:=false}" # Print the file contents in a code block

[[ $LANGUAGE ]] && CODE_BLOCK=true

[[ $TITLE ]] && echo "**$TITLE**"
$CODE_BLOCK && echo '```'"${LANGUAGE:-}"
cat "$FILE"
$CODE_BLOCK && echo '```'

exit 0
