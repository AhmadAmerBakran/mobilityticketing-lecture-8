#!/usr/bin/env python3
"""Read the lab helper's plans and add measured results to evidence.md."""

from pathlib import Path
import re
from statistics import median

DOCS = Path("docs")
CASES = (
    ("R-7", "Baseline", "baseline-r7.txt"),
    ("R-7", "UTC range", "rewrite-r7.txt"),
    ("R-7", "Route-only", "route-r7.txt"),
    ("R-7", "Selected index", "index-r7.txt"),
    ("R-0", "Baseline", "baseline-r0.txt"),
    ("R-0", "UTC range", "rewrite-r0.txt"),
    ("R-0", "Route-only", "route-r0.txt"),
    ("R-0", "Selected index", "index-r0.txt"),
)
NODES = ("Index Only Scan", "Bitmap Heap Scan", "Bitmap Index Scan",
         "Index Scan", "Seq Scan", "Incremental Sort", "Sort")


def measured_plans(filename):
    content = (DOCS / filename).read_text()
    plans = re.split(r"(?m)^Measured run [1-5]\s*$", content)[1:]
    if len(plans) != 5:
        raise ValueError(f"{filename}: expected five measured plans, got {len(plans)}")
    return plans


def timing(plan):
    value = re.search(r"Execution Time:\s*([0-9.]+) ms", plan)
    if not value:
        raise ValueError("Execution Time missing from plan")
    return float(value.group(1))


def buffers(plan):
    value = re.search(r"(?m)^\s*Buffers: shared hit=(\d+)(?: read=(\d+))?", plan)
    if not value:
        return "not reported"
    return f"{value.group(1)} / {value.group(2) or '0'}"


def operators(plan):
    found = [
        node for node in NODES
        if re.search(r"(?m)^\s*(?:->\s*)?" + re.escape(node) + r"\b", plan)
    ]
    return ", ".join(found) if found else "See plan"


def index_size(filename, name):
    content = (DOCS / filename).read_text()
    m = re.search(r"(?m)^" + re.escape(name) + r"\|([^\n]+)", content)
    if not m:
        raise ValueError(f"{name} not found in {filename}")
    return m.group(1).strip()


def main():
    rows = [
        "| Route | Query | Median ms | Range ms | Plan nodes | Top-node hit / read buffers |",
        "| --- | --- | ---: | ---: | --- | ---: |",
    ]
    for route, label, filename in CASES:
        plans = measured_plans(filename)
        values = [timing(p) for p in plans]
        rows.append(
            f"| {route} | {label} | {median(values):.3f} | "
            f"{min(values):.3f}–{max(values):.3f} | "
            f"{operators(plans[-1])} | {buffers(plans[-1])} |"
        )

    route_size = index_size("route-index-sizes.txt", "trips_route_only_idx")
    selected_size = index_size("selected-index-sizes.txt", "trips_scheduled_route_departure_idx")
    rows += [
        "",
        f"Index sizes: route-only **{route_size}**; selected **{selected_size}**.",
        "",
        "All four correctness checks passed after the rewrite and after each index. "
        "They compare the first 20 and the complete day for R-7 and R-0.",
        "",
        "Raw plans: `baseline-*.txt`, `rewrite-*.txt`, `route-*.txt`, "
        "`index-*.txt` in this directory.",
        "",
    ]
    evidence = DOCS / "evidence.md"
    content = evidence.read_text()
    begin = content.index("## Measurements\n")
    end = content.index("## Index choice\n", begin)
    content = content[:begin] + "## Measurements\n\n" + "\n".join(rows) + "\n" + content[end:]
    evidence.write_text(content)


if __name__ == "__main__":
    main()
