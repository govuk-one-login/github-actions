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
    GIT_CONFIG_COUNT=2 \
      GIT_CONFIG_KEY_0=url.https://github.com/.insteadOf \
      GIT_CONFIG_VALUE_0=git@github.com: \
      GIT_CONFIG_KEY_1=url.https://github.com/.insteadOf \
      GIT_CONFIG_VALUE_1=ssh://git@github.com/ \
      terraform init -backend=false
    echo "Validating Terraform"
    terraform validate
  )
done
