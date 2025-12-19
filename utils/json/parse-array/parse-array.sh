set -eu

: "${STRING}" # The string to parse into a JSON array

read -ra values <<< "$(tr '\n' ' ' <<< "$STRING")"
jq --raw-input < <(IFS=$'\n' && echo "${values[*]}") | jq --slurp --compact-output
