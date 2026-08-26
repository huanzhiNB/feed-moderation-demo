#!/usr/bin/env python3
"""Summarize "appear-to-play latency" numbers logged by FeedItemCell.

Usage:
    python3 scripts/parse_latency.py perf-logs/slow_run1.log perf-logs/slow_run2.log
    python3 scripts/parse_latency.py perf-logs/*.log --exclude-first

Reads one or more log files (captured via `xcrun simctl spawn booted log stream`
or copied from the Xcode console), extracts every
"cell <index> appear-to-play latency: <ms> ms" line, and prints count/mean/
median/p90/max per file plus a combined total across all files given in one
invocation (treat that invocation as one "condition").
"""

import argparse
import re
import statistics
import sys

PATTERN = re.compile(r"cell (\d+) appear-to-play latency: ([\d.]+) ms")


def extract(path):
    samples = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = PATTERN.search(line)
            if match:
                samples.append((int(match.group(1)), float(match.group(2))))
    return samples


def summarize(label, values):
    if not values:
        print(f"{label}: no samples found")
        return
    print(
        f"{label}: n={len(values)} "
        f"mean={statistics.mean(values):.1f}ms "
        f"median={statistics.median(values):.1f}ms "
        f"p90={sorted(values)[int(len(values) * 0.9) - 1 if len(values) > 1 else 0]:.1f}ms "
        f"max={max(values):.1f}ms min={min(values):.1f}ms"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", help="log file(s) for one condition/run")
    parser.add_argument(
        "--exclude-first",
        action="store_true",
        help="drop each file's cell index 0 (cold start, no ±1 prefetch head start)",
    )
    args = parser.parse_args()

    all_values = []
    for path in args.logs:
        samples = extract(path)
        if args.exclude_first:
            samples = [(index, ms) for index, ms in samples if index != 0]
        values = [ms for _, ms in samples]
        summarize(path, values)
        all_values.extend(values)

    if len(args.logs) > 1:
        print("-" * 60)
        summarize("COMBINED", all_values)


if __name__ == "__main__":
    sys.exit(main())
