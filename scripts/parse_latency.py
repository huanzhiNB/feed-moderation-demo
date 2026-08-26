#!/usr/bin/env python3
"""Summarize "appear-to-play latency" and frame-hitch numbers logged by the app.

Usage:
    python3 scripts/parse_latency.py perf-logs/config_a_run1.log perf-logs/config_a_run2.log
    python3 scripts/parse_latency.py perf-logs/*.log --exclude-first

Reads one or more log files (captured via `xcrun simctl spawn booted log stream`
or copied from the Xcode console) and extracts two kinds of lines:
  - FeedItemCell: "cell <index> appear-to-play latency: <ms> ms"
  - FrameHitchMonitor: "hitch <ms> ms (frame took <ms> ms, expected <ms> ms)"
Prints count/mean/median/p90/max for each, per file, plus a combined total
across all files given in one invocation (treat that invocation as one
"condition"/window config).
"""

import argparse
import re
import statistics
import sys

LATENCY_PATTERN = re.compile(r"cell (\d+) appear-to-play latency: ([\d.]+) ms")
HITCH_PATTERN = re.compile(r"hitch ([\d.]+) ms \(frame took")


def extract_latency(path):
    samples = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = LATENCY_PATTERN.search(line)
            if match:
                samples.append((int(match.group(1)), float(match.group(2))))
    return samples


def extract_hitches(path):
    values = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = HITCH_PATTERN.search(line)
            if match:
                values.append(float(match.group(1)))
    return values


def summarize(label, values, unit="ms"):
    if not values:
        print(f"{label}: no samples found")
        return
    print(
        f"{label}: n={len(values)} "
        f"mean={statistics.mean(values):.1f}{unit} "
        f"median={statistics.median(values):.1f}{unit} "
        f"p90={sorted(values)[int(len(values) * 0.9) - 1 if len(values) > 1 else 0]:.1f}{unit} "
        f"max={max(values):.1f}{unit} min={min(values):.1f}{unit} "
        f"total={sum(values):.1f}{unit}"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("logs", nargs="+", help="log file(s) for one condition/run")
    parser.add_argument(
        "--exclude-first",
        action="store_true",
        help="drop each file's cell index 0 (cold start, no prefetch head start)",
    )
    args = parser.parse_args()

    all_latency = []
    all_hitches = []
    for path in args.logs:
        samples = extract_latency(path)
        if args.exclude_first:
            samples = [(index, ms) for index, ms in samples if index != 0]
        latency_values = [ms for _, ms in samples]
        hitch_values = extract_hitches(path)

        summarize(f"{path} [latency]", latency_values)
        summarize(f"{path} [hitch]", hitch_values)
        all_latency.extend(latency_values)
        all_hitches.extend(hitch_values)

    if len(args.logs) > 1:
        print("-" * 60)
        summarize("COMBINED [latency]", all_latency)
        summarize("COMBINED [hitch]", all_hitches)


if __name__ == "__main__":
    sys.exit(main())
