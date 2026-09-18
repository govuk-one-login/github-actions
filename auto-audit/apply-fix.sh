#!/usr/bin/env bash

set -euo pipefail

BUCKET="${1:?bucket required: safe | forceNonBreaking | breaking}"
AUDIT_SUMMARY="${AUDIT_SUMMARY:-audit-summary.json}"
PACKAGE_JSON_PATH="${PACKAGE_JSON_PATH:-package.json}"

export BUCKET
export AUDIT_SUMMARY
export PACKAGE_JSON_PATH

case "$BUCKET" in
  safe)
    BRANCH="auto-audit/fix-safe"
    TITLE="chore(security): in-range npm audit fixes"
    COMMIT_MSG="chore(security): apply in-range npm audit fixes"
    DESC="Applies \`npm audit fix\` for vulnerabilities whose fix is within the stated SemVer range."
    ;;
  forceNonBreaking)
    BRANCH="auto-audit/fix-force"
    TITLE="chore(security): non-breaking out-of-range upgrades"
    COMMIT_MSG="chore(security): upgrade out-of-range deps (non-breaking)"
    DESC="Upgrades dependencies whose fix is outside the stated SemVer range but is not SemVer-major."
    ;;
  breaking)
    BRANCH="auto-audit/fix-breaking"
    TITLE="chore(security)!: SemVer-major upgrades for vulnerabilities"
    COMMIT_MSG="chore(security)!: apply SemVer-major upgrades for vulnerabilities"
    DESC="Potentially breaking. Applies SemVer-major upgrades. Review each package's changelog before merging."
    ;;
  *)
    echo "Unknown bucket: $BUCKET" >&2
    exit 2
    ;;
esac

if [[ ! -f "$PACKAGE_JSON_PATH" ]]; then
  echo "Configured package.json does not exist: $PACKAGE_JSON_PATH" >&2
  exit 1
fi

if [[ ! -f "$AUDIT_SUMMARY" ]]; then
  echo "Audit summary does not exist: $AUDIT_SUMMARY" >&2
  exit 1
fi

if [[ -z "${PR_FILES:-}" ]]; then
  echo "PR_FILES was not provided" >&2
  exit 1
fi

PKG_PATHS=()

while IFS= read -r package_path; do
  if [[ -n "$package_path" ]]; then
    PKG_PATHS+=("$package_path")
  fi
done <<< "$PR_FILES"

if [[ "${#PKG_PATHS[@]}" -eq 0 ]]; then
  echo "PR_FILES did not contain any package files" >&2
  exit 1
fi

PACKAGE_DIRECTORY="$(dirname "$PACKAGE_JSON_PATH")"

echo "Applying fixes from package directory: $PACKAGE_DIRECTORY"
echo "Package files monitored for changes:"

for package_path in "${PKG_PATHS[@]}"; do
  echo "  $package_path"
done

if [[ "$BUCKET" = "safe" ]]; then
  (
    cd "$PACKAGE_DIRECTORY"

    HAS_WORKSPACES="$(
      node -e "
        const fs = require('fs');
        const packageJson = JSON.parse(
          fs.readFileSync('package.json', 'utf8')
        );

        const workspaces = packageJson.workspaces;

        const hasWorkspaces =
          Array.isArray(workspaces)
            ? workspaces.length > 0
            : Array.isArray(workspaces?.packages)
              ? workspaces.packages.length > 0
              : false;

        process.stdout.write(String(hasWorkspaces));
      "
    )"

    if [[ "$HAS_WORKSPACES" = "true" ]]; then
      npm audit fix \
        --ignore-scripts \
        --workspaces \
        --include-workspace-root || true
    else
      npm audit fix --ignore-scripts || true
    fi
  )
else
  node << 'JS'
const fs = require('fs');
const path = require('path');
const {execFileSync} = require('child_process');

const bucket = process.env.BUCKET;
const auditSummaryPath = process.env.AUDIT_SUMMARY;
const packageJsonPath =
  process.env.PACKAGE_JSON_PATH || 'package.json';

const repositoryRoot = process.cwd();
const rootPackagePath = path.resolve(
  repositoryRoot,
  packageJsonPath,
);
const rootPackageDirectory = path.dirname(rootPackagePath);

const rootPackage = JSON.parse(
  fs.readFileSync(rootPackagePath, 'utf8'),
);

const summary = JSON.parse(
  fs.readFileSync(auditSummaryPath, 'utf8'),
);

const targets = [
  ...new Set(
    (summary[bucket] || [])
      .map(entry => entry.target)
      .filter(Boolean),
  ),
];

if (targets.length === 0) {
  console.log(
    `No targets resolved for bucket ${bucket}; nothing to do.`,
  );
  process.exit(0);
}

const packageFiles = (process.env.PR_FILES || '')
  .split(/\r?\n/)
  .map(file => file.trim())
  .filter(file => file.endsWith('package.json'))
  .map(file => path.resolve(repositoryRoot, file))
  .filter(file => fs.existsSync(file));

const workspacePackageFiles = packageFiles.filter(
  file => file !== rootPackagePath,
);

function dependenciesFor(packageJson) {
  return {
    ...(packageJson.dependencies || {}),
    ...(packageJson.devDependencies || {}),
    ...(packageJson.optionalDependencies || {}),
  };
}

function packageNameFromTarget(target) {
  const versionSeparator = target.lastIndexOf('@');

  return versionSeparator > 0
    ? target.slice(0, versionSeparator)
    : target;
}

function runNpmInstall(args) {
  execFileSync(
    'npm',
    ['install', '--ignore-scripts', '--save-exact', ...args],
    {
      cwd: rootPackageDirectory,
      stdio: 'inherit',
    },
  );
}

for (const target of targets) {
  const packageName = packageNameFromTarget(target);
  let installed = false;

  for (const workspacePackageFile of workspacePackageFiles) {
    let workspacePackage;

    try {
      workspacePackage = JSON.parse(
        fs.readFileSync(workspacePackageFile, 'utf8'),
      );
    } catch (error) {
      console.warn(
        `Unable to read ${workspacePackageFile}: ${error.message}`,
      );
      continue;
    }

    const workspaceDependencies =
      dependenciesFor(workspacePackage);

    if (!(packageName in workspaceDependencies)) {
      continue;
    }

    const workspaceDirectory =
      path.dirname(workspacePackageFile);

    const relativeWorkspaceDirectory = path.relative(
      rootPackageDirectory,
      workspaceDirectory,
    );

    if (
      relativeWorkspaceDirectory.startsWith('..') ||
      path.isAbsolute(relativeWorkspaceDirectory)
    ) {
      console.warn(
        `Workspace is outside the configured package root: ${workspaceDirectory}`,
      );
      continue;
    }

    console.log(
      `Installing ${target} in workspace ${relativeWorkspaceDirectory}`,
    );

    runNpmInstall([
      target,
      '--workspace',
      relativeWorkspaceDirectory,
    ]);

    installed = true;
    break;
  }

  if (installed) {
    continue;
  }

  const rootDependencies = dependenciesFor(rootPackage);

  if (packageName in rootDependencies) {
    console.log(`Installing ${target} in the package root`);
    runNpmInstall([target]);
    continue;
  }

  console.warn(
    `${packageName} is not a direct dependency in the configured package root or any discovered workspace; skipping it as transitive-only.`,
  );
}
JS
fi

GITHUB_OUTPUT="${GITHUB_OUTPUT:-/dev/stdout}"

CHANGED_FILES="$(
  git diff --name-only -- "${PKG_PATHS[@]}"
)"

if [[ -z "$CHANGED_FILES" ]]; then
  echo "No dependency changes produced for bucket $BUCKET; no PR needed."
  echo "changed=false" >> "$GITHUB_OUTPUT"
  exit 0
fi

echo "Changed files:"

while IFS= read -r changed_file; do
  echo "  $changed_file"
done <<< "$CHANGED_FILES"

BODY_PATH="${RUNNER_TEMP:-/tmp}/pr-body-${BUCKET}.md"
RUN_URL="${GITHUB_SERVER_URL:-https://github.com}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"

{
  printf '%s\n\n%s\n\n' \
    "Automated PR from the check-vulnerabilities workflow." \
    "$DESC"

  node << 'JS'
const fs = require('fs');

const summary = JSON.parse(
  fs.readFileSync(process.env.AUDIT_SUMMARY, 'utf8'),
);

const entries = summary[process.env.BUCKET] || [];

console.log(
  entries
    .map(entry =>
      entry.target
        ? `- \`${entry.name}\` -> \`${entry.target}\` (${entry.severity})`
        : `- \`${entry.name}\` (${entry.severity})`,
    )
    .join('\n'),
);
JS

  printf '\n---\nRaised by run: %s\n' "$RUN_URL"
} > "$BODY_PATH"

{
  echo "changed=true"
  echo "branch=$BRANCH"
  echo "title=$TITLE"
  echo "commit_message=$COMMIT_MSG"
  echo "body_path=$BODY_PATH"
} >> "$GITHUB_OUTPUT"
