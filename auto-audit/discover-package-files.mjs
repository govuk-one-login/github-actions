import {
  appendFileSync,
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";

const repositoryRoot = resolve(process.env.REPOSITORY_ROOT ?? process.cwd());

const configuredPackageJsonPaths =
  process.env.PACKAGE_JSON_PATHS ??
  process.env.PACKAGE_JSON_PATH ??
  "package.json";

const githubOutput = process.env.GITHUB_OUTPUT;

function normalisePath(filePath) {
  return filePath.split(sep).join("/");
}

function readPackageJson(filePath) {
  try {
    return JSON.parse(readFileSync(filePath, "utf8"));
  } catch (error) {
    throw new Error(`Unable to read ${filePath}: ${error.message}`);
  }
}

function getConfiguredPackageFiles(value) {
  const packageFiles = value
    .split(/\r?\n/)
    .map((filePath) => filePath.trim())
    .filter(Boolean);

  if (packageFiles.length === 0) {
    throw new Error(
      "PACKAGE_JSON_PATHS did not contain any package.json paths"
    );
  }

  return [...new Set(packageFiles)];
}

function getWorkspacePatterns(packageJson) {
  if (Array.isArray(packageJson.workspaces)) {
    return packageJson.workspaces;
  }

  if (
    packageJson.workspaces &&
    Array.isArray(packageJson.workspaces.packages)
  ) {
    return packageJson.workspaces.packages;
  }

  return [];
}

function globToRegex(pattern) {
  const normalised = normalisePath(pattern)
    .replace(/\/package\.json$/, "")
    .replace(/\/$/, "");

  const escaped = normalised
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, "__DOUBLE_STAR__")
    .replace(/\*/g, "[^/]*")
    .replace(/__DOUBLE_STAR__/g, ".*");

  return new RegExp(`^${escaped}$`);
}

function walkDirectories(root) {
  const directories = [];

  function walk(currentPath) {
    const entries = readdirSync(currentPath, {
      withFileTypes: true,
    });

    for (const entry of entries) {
      if (!entry.isDirectory()) {
        continue;
      }

      if (entry.name === "node_modules" || entry.name === ".git") {
        continue;
      }

      const fullPath = join(currentPath, entry.name);

      directories.push(fullPath);
      walk(fullPath);
    }
  }

  walk(root);

  return directories;
}

function resolveWorkspacePackageFiles(rootPackageDirectory, workspacePatterns) {
  if (workspacePatterns.length === 0) {
    return [];
  }

  const directories = walkDirectories(rootPackageDirectory);
  const packageFiles = new Set();

  for (const pattern of workspacePatterns) {
    if (typeof pattern !== "string" || pattern.startsWith("!")) {
      continue;
    }

    const patternRegex = globToRegex(pattern);

    for (const directory of directories) {
      const relativeDirectory = normalisePath(
        relative(rootPackageDirectory, directory)
      );

      if (!patternRegex.test(relativeDirectory)) {
        continue;
      }

      const workspacePackageJson = join(directory, "package.json");

      if (
        existsSync(workspacePackageJson) &&
        statSync(workspacePackageJson).isFile()
      ) {
        packageFiles.add(workspacePackageJson);
      }
    }
  }

  return [...packageFiles];
}

function writeOutput(name, value) {
  if (!githubOutput) {
    return;
  }

  appendFileSync(githubOutput, `${name}=${value}\n`);
}

function writeMultilineOutput(name, value) {
  if (!githubOutput) {
    return;
  }

  const delimiter = `AUTO_AUDIT_${name.toUpperCase().replaceAll("-", "_")}_EOF`;

  appendFileSync(
    githubOutput,
    `${name}<<${delimiter}\n${value}\n${delimiter}\n`
  );
}

const configuredPackageFiles = getConfiguredPackageFiles(
  configuredPackageJsonPaths
);

console.log("Configured package.json files:");

for (const configuredPackageFile of configuredPackageFiles) {
  console.log(` - ${configuredPackageFile}`);
}

const discoveredPackageFiles = new Set();
const workspacePatternsByRoot = new Map();

for (const configuredPackageFile of configuredPackageFiles) {
  const packageJsonPath = resolve(repositoryRoot, configuredPackageFile);

  if (!existsSync(packageJsonPath)) {
    throw new Error(
      `Configured package.json does not exist: ${configuredPackageFile}`
    );
  }

  if (!statSync(packageJsonPath).isFile()) {
    throw new Error(
      `Configured package.json is not a file: ${configuredPackageFile}`
    );
  }

  const packageJson = readPackageJson(packageJsonPath);
  const packageDirectory = dirname(packageJsonPath);
  const workspacePatterns = getWorkspacePatterns(packageJson);

  discoveredPackageFiles.add(packageJsonPath);

  const workspacePackageFiles = resolveWorkspacePackageFiles(
    packageDirectory,
    workspacePatterns
  );

  for (const workspacePackageFile of workspacePackageFiles) {
    discoveredPackageFiles.add(workspacePackageFile);
  }

  workspacePatternsByRoot.set(
    normalisePath(relative(repositoryRoot, packageJsonPath)),
    workspacePatterns
  );
}

const uniquePackageFiles = [...discoveredPackageFiles].sort();

const relativePackageFiles = uniquePackageFiles.map((filePath) =>
  normalisePath(relative(repositoryRoot, filePath))
);

const lockFiles = uniquePackageFiles
  .map((filePath) => join(dirname(filePath), "package-lock.json"))
  .filter((filePath) => existsSync(filePath) && statSync(filePath).isFile())
  .map((filePath) => normalisePath(relative(repositoryRoot, filePath)));

console.log("Package.json files that will be evaluated:");

for (const packageFile of relativePackageFiles) {
  console.log(` - ${packageFile}`);
}

for (const [rootPackageFile, workspacePatterns] of workspacePatternsByRoot) {
  if (workspacePatterns.length === 0) {
    console.log(`${rootPackageFile} does not declare npm workspaces.`);

    continue;
  }

  console.log(`Workspace patterns declared by ${rootPackageFile}:`);

  for (const pattern of workspacePatterns) {
    console.log(` - ${pattern}`);
  }
}

const filesForPullRequest = [
  ...new Set([...relativePackageFiles, ...lockFiles]),
]
  .sort()
  .join("\n");

const packageDirectories = [
  ...new Set(
    relativePackageFiles.map((filePath) => {
      const packageDirectory = dirname(filePath);

      return packageDirectory === "." ? "." : normalisePath(packageDirectory);
    })
  ),
].sort();

writeOutput("package-json-files", JSON.stringify(relativePackageFiles));

writeOutput("package-directories", JSON.stringify(packageDirectories));

writeMultilineOutput("pr-files", filesForPullRequest);
