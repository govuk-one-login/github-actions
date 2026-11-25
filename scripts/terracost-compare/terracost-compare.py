#!/usr/bin/env python3
"""Compare Terracost cost estimates of two checkouts and report the difference.

Usage: terracost-compare.py <terracost-binary> <base-dir> <base-label> <head-dir> <head-label> <module>...
Each <module> is a Terraform root module directory, relative to the checkout root. A module that
does not exist in a checkout counts as empty (for example a module added by the change).
Reads .tf files only (Terracost HCL mode): no plan, no state, no AWS access.

Prints a Markdown summary. When run in GitHub Actions it also appends the summary to the job
summary and sets the step outputs "summary" and "cost-difference-usd" (for example "1.00").
"""
import os
import re
import subprocess
import sys

RESOURCE_LINE = re.compile(r"^(\S.*): [\d.eE+-]+ -> ([\d.eE+-]+)$")  # "<address>: <prior> -> <planned>"


def estimate(terracost, checkout, modules):
    """Return {"<module>/<resource address>": planned cost} for every priced resource."""
    costs = {}
    for module in modules:
        if not os.path.isdir(f"{checkout}/{module}"):
            continue
        out = subprocess.run(
            [terracost, "-provider", "aws", "-estimate-hcl", f"{checkout}/{module}"],
            capture_output=True, text=True, check=True,
        ).stdout
        for line in out.splitlines():
            if m := RESOURCE_LINE.match(line):
                costs[f"{module}/{m[1]}"] = float(m[2])
    return costs


def usd(amount, sign=""):
    """Format as dollars, escaped (\\$) so GitHub Markdown does not read $...$ as math."""
    return f"{'-' if amount < 0 else sign}\\${abs(amount):.2f}"


terracost, base_dir, base, head_dir, head, *modules = sys.argv[1:]
base_costs, head_costs = estimate(terracost, base_dir, modules), estimate(terracost, head_dir, modules)
base_total, head_total = sum(base_costs.values()), sum(head_costs.values())
difference = round(head_total - base_total, 2) + 0  # "+ 0" turns -0.0 into 0.0

changes = []
for address in sorted(base_costs.keys() | head_costs.keys()):
    before, after = base_costs.get(address, 0.0), head_costs.get(address, 0.0)
    if abs(after - before) > 0.005:
        kind = "added" if address not in base_costs else "removed" if address not in head_costs else "changed"
        changes.append(f"| {kind} | `{address}` | {usd(before)} | {usd(after)} | {usd(after - before, '+')} |")

lines = [
    "| | Priced resources | Total |", "|---|---|---|",
    f"| `{base}` | {len(base_costs)} | {usd(base_total)} |",
    f"| `{head}` | {len(head_costs)} | {usd(head_total)} |",
    f"| **Difference** | | **{usd(difference, '+')}** |", "",
]
if changes:
    lines += [f"| Change | Resource | `{base}` | `{head}` | Difference |", "|---|---|---|---|---|", *changes]
else:
    lines.append("No priced resources were added, removed or changed.")
lines += ["", "> Resource types Terracost does not support (for example Kinesis, Firehose, Lambda) are skipped,",
          "> so changes to them do not appear."]
summary = "\n".join(lines)

print(summary)
if path := os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(path, "a") as f:
        f.write(summary + "\n")
if path := os.environ.get("GITHUB_OUTPUT"):
    with open(path, "a") as f:
        f.write(f"cost-difference-usd={difference:.2f}\nsummary<<TERRACOST_EOF\n{summary}\nTERRACOST_EOF\n")
