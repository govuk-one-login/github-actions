set -eu

: "${PARAMETERS}"               # The parameters to parse
: "${ASSOCIATIVE_ARRAY:=false}" # Whether to encode output as a string representing an associative array
: "${LONG_FORMAT:=false}"       # Whether to encode the parameters in the form of "key=key,value='value'" strings
: "${JSON_OUTPUT:=false}"       # Whether to encode the parameters as a JSON key-value map

[[ $PARAMETERS ]] || exit 0

raw_parameters=$(echo -n "${PARAMETERS}")
associative=${ASSOCIATIVE_ARRAY}
long=${LONG_FORMAT}
json=${JSON_OUTPUT}

num_lines=$(wc -l <<< "$raw_parameters")
if [[ $num_lines -le 1 ]]; then
  IFS="|" read -ra key_value_pairs <<< "$raw_parameters"
else
  mapfile -t key_value_pairs <<< "$raw_parameters"
fi

$json && parameters_json="{}" || parameters_array=()

for kvp in "${key_value_pairs[@]}"; do
  IFS="=" read -r name value < <(xargs <<< "$kvp")
  name=$(xargs <<< "$name") && value="$(xargs <<< "$value")"

  if $json; then
    parameters_json=$(
      jq --compact-output --arg key "$name" --arg value "$value" '.[$key]=$value' <<< "$parameters_json"
    )
  else
    value="'$value'"

    if $associative; then
      element="[$name]=$value"
    elif $long; then
      element="key=$name,value=$value"
    else
      element="$name=$value"
    fi

    parameters_array+=("$element")
  fi
done

echo "${parameters_json:-${parameters_array[*]}}"
