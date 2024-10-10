set -eu

: "${STRING}" # The string to parse into a JSON array

tr '\n' ' ' <<< "$STRING" >> "$GITHUB_STEP_SUMMARY"

exit 0

read -ra values < <(tr '\n' ' ' <<< "$STRING")
jq --raw-input < <(IFS=$'\n' && echo "${values[*]}") | jq --slurp --compact-output
