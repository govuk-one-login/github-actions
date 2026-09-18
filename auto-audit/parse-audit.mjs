import fs from "node:fs";

const auditPath = process.env.AUDIT_FILE ?? "audit.json";

const summaryPath = process.env.AUDIT_SUMMARY_FILE ?? "audit-summary.json";

const audit = JSON.parse(fs.readFileSync(auditPath, "utf8"));

const vulns = audit.vulnerabilities || {};

const advisoriesFor = (v) =>
  (v.via || [])
    .filter((x) => typeof x === "object" && x !== null)
    .map((a) => ({
      title: a.title,
      url: a.url,
      severity: a.severity,
      range: a.range,
      cvss: a.cvss?.score,
    }));

const summary = {
  safe: [],
  forceNonBreaking: [],
  breaking: [],
  unfixable: [],
};

for (const [name, v] of Object.entries(vulns)) {
  const fa = v.fixAvailable;

  const base = {
    name,
    severity: v.severity,
    range: v.range,
  };

  if (fa === false) {
    summary.unfixable.push({
      ...base,
      advisories: advisoriesFor(v),
    });
  } else if (fa === true) {
    summary.safe.push(base);
  } else if (fa && typeof fa === "object") {
    const entry = {
      ...base,
      target: `${fa.name}@${fa.version}`,
      isSemVerMajor: !!fa.isSemVerMajor,
    };

    (fa.isSemVerMajor ? summary.breaking : summary.forceNonBreaking).push(
      entry
    );
  }
}

fs.writeFileSync(summaryPath, JSON.stringify(summary, null, 2));

console.log(JSON.stringify(summary, null, 2));

const buckets = ["safe", "forceNonBreaking", "breaking"].filter(
  (bucket) => summary[bucket].length > 0
);

const out = process.env.GITHUB_OUTPUT;

if (out) {
  fs.appendFileSync(
    out,
    [
      `safe_count=${summary.safe.length}`,
      `force_count=${summary.forceNonBreaking.length}`,
      `breaking_count=${summary.breaking.length}`,
      `unfixable_count=${summary.unfixable.length}`,
      `buckets=${JSON.stringify(buckets)}`,
      "",
    ].join("\n")
  );
}
