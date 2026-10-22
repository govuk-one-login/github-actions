#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$1"
export TF_PLUGIN_CACHE_DIR="/tmp/terraform-plugin-cache"
mkdir -p "${TF_PLUGIN_CACHE_DIR}"

dirs=$(find "${ROOT_DIR}" -type f -name '*.tf' -not -path '*/.terraform/*' \
  -not -path '*/modules/*' -printf '%h\n' | sort -u)

if [ -z "${dirs}" ]; then
  echo "No Terraform directories found"
  exit 0
fi

echo "${dirs}" | while read -r dir; do
  echo -e "\nValidating ${dir}\n"
  (
    cd "${dir}"
    echo "Initalising Terraform"
    git_config=(
      "GIT_CONFIG_COUNT=2"
      "GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf"
      "GIT_CONFIG_VALUE_0=git@github.com:"
      "GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf"
      "GIT_CONFIG_VALUE_1=ssh://git@github.com/"
    )
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
      authorization=$(printf 'x-access-token:%s' "${GITHUB_TOKEN}" | base64 | tr -d '\n')
      git_config[0]="GIT_CONFIG_COUNT=3"
      git_config+=(
        "GIT_CONFIG_KEY_2=http.https://github.com/.extraheader"
        "GIT_CONFIG_VALUE_2=AUTHORIZATION: basic ${authorization}"
      )
    fi
    env "${git_config[@]}" \
      terraform init -backend=false
    echo "Validating Terraform"
    terraform validate
  )
done
