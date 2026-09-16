import {
  appendFileSync,
  existsSync,
  readFileSync,
  readdirSync,
  statSync,
} from "node:fs";
import { dirname, join, relative, resolve, sep } from "node:path";

const repositoryRoot = resolve(process.env.REPOSITORY_ROOT ?? process.cwd());

const configuredPackageJson = process.env.PACKAGE_JSON_PATH ?? "package.json";

const githubOutput = process.env.GITHUB_OUTPUT;

function normalisePath(path) {
  return path.split(sep).join("/");
}

function readPackageJson(path) {
  try {
    return JSON.parse(readFileSync(path, "utf8"));
  } catch (error) {
    throw new Error(`Unable to read ${path}: ${error.message}`);
  }
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

const rootPackageJsonPath = resolve(repositoryRoot, configuredPackageJson);

if (!existsSync(rootPackageJsonPath)) {
  throw new Error(
    `Configured package.json does not exist: ${configuredPackageJson}`
  );
}

const rootPackage = readPackageJson(rootPackageJsonPath);
const rootPackageDirectory = dirname(rootPackageJsonPath);
const workspacePatterns = getWorkspacePatterns(rootPackage);

const discoveredPackageFiles = [
  rootPackageJsonPath,
  ...resolveWorkspacePackageFiles(rootPackageDirectory, workspacePatterns),
];

const uniquePackageFiles = [...new Set(discoveredPackageFiles)].sort();

const relativePackageFiles = uniquePackageFiles.map((path) =>
  normalisePath(relative(repositoryRoot, path))
);

const lockFiles = uniquePackageFiles
  .map((path) => join(dirname(path), "package-lock.json"))
  .filter((path) => existsSync(path))
  .map((path) => normalisePath(relative(repositoryRoot, path)));

console.log("Package.json files that will be evaluated:");

for (const packageFile of relativePackageFiles) {
  console.log(` - ${packageFile}`);
}

if (workspacePatterns.length === 0) {
  console.log("The configured package.json does not declare npm workspaces.");
} else {
  console.log("Workspace patterns:");

  for (const pattern of workspacePatterns) {
    console.log(` - ${pattern}`);
  }
}

const filesForPullRequest = [
  ...new Set([...relativePackageFiles, ...lockFiles]),
].join("\n");

const packageDirectories = [
  ...new Set(
    relativePackageFiles.map((path) => {
      const packageDirectory = dirname(path);

      return packageDirectory === "." ? "." : normalisePath(packageDirectory);
    })
  ),
];

writeOutput("package-json-files", JSON.stringify(relativePackageFiles));

writeOutput("package-directories", JSON.stringify(packageDirectories));

if (githubOutput) {
  appendFileSync(
    githubOutput,
    `pr-files<<AUTO_AUDIT_EOF\n${filesForPullRequest}\nAUTO_AUDIT_EOF\n`
  );
}
