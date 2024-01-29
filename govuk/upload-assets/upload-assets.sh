set -eu

govuk_fe_version=$(jq --raw-output .version node_modules/govuk-frontend/package.json | tee govuk_fe_version.txt)

[[ $PATH_TO_SASS ]] && sed -i \
  "s/\(@import .*\/node_modules\/govuk-frontend\/govuk\/base\";\)/\$govuk-assets-path: \"\/v-$govuk_fe_version\/\";\n\1/" \
  "$PATH_TO_SASS"

$PKG_MGR run build

pushd dist && zip -r ../public public && popd
md5sum public.zip | cut -c -32 > zipsum

aws kms sign --key-id "$SIGNING_KEY" --message fileb://zipsum --signing-algorithm RSASSA_PSS_SHA_256 \
  --message-type RAW --output text --query Signature | base64 --decode > ZipSignature

zip -r "$STACK_NAME" public.zip ZipSignature govuk_fe_version.txt

aws s3 cp "$STACK_NAME.zip" "s3://$ARTIFACT_BUCKET/$STACK_NAME.zip" \
  --metadata "repository=$GITHUB_REPOSITORY,commitsha=$GITHUB_SHA"

echo "Assets ZIP file uploaded"
