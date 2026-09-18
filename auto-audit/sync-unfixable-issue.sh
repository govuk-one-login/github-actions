#!/usr/bin/env bash

set -euo pipefail

AUDIT_SUMMARY="${AUDIT_SUMMARY:-audit-summary.json}"
GH_REPO="${GH_REPO:?GH_REPO must be provided}"

export AUDIT_SUMMARY GH_REPO

if [[ ! -f "$AUDIT_SUMMARY" ]]; then
  echo "Audit summary does not exist: $AUDIT_SUMMARY" >&2
  exit 1
fi

LABEL="auto-audit-unfixable"
TITLE="auto-audit: unfixable npm vulnerabilities"
gh label create "$LABEL" --color B60205 \
  --description "Vulnerabilities with no upstream fix available" 2> /dev/null || true

EXISTING=$(gh issue list --label "$LABEL" --state open --json number --jq '.[0].number')
COUNT=$(node -e "console.log(JSON.parse(require('fs').readFileSync(process.env.AUDIT_SUMMARY, 'utf8')).unfixable.length)")

if [[ "$COUNT" = "0" ]]; then
  if [[ -n "$EXISTING" ]]; then
    gh issue close "$EXISTING" \
      --comment "All previously unfixable vulnerabilities now have upstream fixes available."
  fi
  exit 0
fi

LIST=$(
  node << 'JS'
const s = JSON.parse(require('fs').readFileSync(process.env.AUDIT_SUMMARY, 'utf8'));
const out = s.unfixable.map(e => {
  const head = `### \`${e.name}\` - ${e.severity}` + (e.range ? ` (vulnerable: \`${e.range}\`)` : '');
  const advs = (e.advisories || []).map(a => {
    const cvss = a.cvss != null ? ` · CVSS ${a.cvss}` : '';
    return `- [${a.title}](${a.url}) - ${a.severity}${cvss}`;
  }).join('\n');
  return head + '\n' + (advs || '_(no advisory details captured)_');
}).join('\n\n');
console.log(out);
JS
)

RUN_URL="${GITHUB_SERVER_URL}/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}"
BODY=$'`npm audit` reports vulnerabilities with **no upstream fix available** (`fixAvailable: false`). These need manual triage - pinning, patching, swapping the dependency, or accepting the risk.\n\n'"$LIST"$'\n\n---\nLast updated by run: '"$RUN_URL"

if [[ -n "$EXISTING" ]]; then
  gh issue edit "$EXISTING" --body "$BODY"
else
  gh issue create --title "$TITLE" --label "$LABEL" --body "$BODY"
fi
