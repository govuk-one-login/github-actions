set -eu

: "${DICTIONARY}"      # The dictionary containing the keys and values to map
: "${KEY_FILTER:-}"    # The filter regex to select the keys to map
: "${KEY_TRANSFORM:-}" # The transform regex to apply to the keys
: "${VALUE_MAP:-[]}"   # The mapping of values to the new values

jq --compact-output \
  --arg keyFilter "$KEY_FILTER" --arg keyTransform "$KEY_TRANSFORM" \
  --argjson valueMap "$VALUE_MAP" \
  'with_entries(
    if $keyFilter != "" then
      select(.key | match($keyFilter))
    else . end |

    if $keyTransform != "" then
      .key = (.key | match($keyTransform) | .captures[0].string)
    else . end |

    if $valueMap != [] then
      .value = ($valueMap[.value] // .value)
    else . end
  )' <<< "$DICTIONARY"
