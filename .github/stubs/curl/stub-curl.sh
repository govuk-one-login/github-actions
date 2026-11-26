#!/usr/bin/env bash

set -eu

arguments_file="$RUNNER_TEMP/curl-arguments"
body_file="$RUNNER_TEMP/curl-body.json"

: > "$arguments_file"

while [[ ${1:-} ]]; do
  printf '%s\n' "$1" >> "$arguments_file"

  if [[ $1 == --data-binary ]]; then
    shift
    printf '%s\n' "$1" > "$body_file"
  fi

  shift
done

printf 'HTTP/1.1 200 OK\n\n'
