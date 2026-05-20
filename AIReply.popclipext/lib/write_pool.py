#!/usr/bin/env python3
"""Create pool.json from user-provided key lines.

Input is treated strictly as data: the shell passes file paths and the
default endpoint as argv, so API keys and endpoints are never interpolated
into executable Python source.
"""
import argparse
import json
import os
import pathlib
import sys


def parse_pool_lines(text: str, default_endpoint: str) -> list[dict[str, str]]:
    pool = []
    endpoint = default_endpoint.rstrip("/")
    for raw_line in text.strip().splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "|" in line:
            api_key, _, item_endpoint = line.partition("|")
            pool.append(
                {
                    "api_key": api_key.strip(),
                    "endpoint": item_endpoint.strip().rstrip("/"),
                }
            )
        else:
            pool.append({"api_key": line, "endpoint": endpoint})
    return [item for item in pool if item["api_key"] and item["endpoint"]]


def write_pool(input_file: str, default_endpoint: str, output_file: str) -> int:
    text = pathlib.Path(input_file).read_text(encoding="utf-8", errors="replace")
    pool = parse_pool_lines(text, default_endpoint)
    output_path = pathlib.Path(output_file).expanduser()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with output_path.open("w", encoding="utf-8") as file:
        json.dump(pool, file, indent=2, ensure_ascii=False)
        file.write("\n")
    os.chmod(output_path, 0o600)
    return len(pool)


def main() -> int:
    parser = argparse.ArgumentParser(description="Write AI Reply key pool JSON")
    parser.add_argument("--input-file", required=True)
    parser.add_argument("--default-endpoint", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    try:
        print(write_pool(args.input_file, args.default_endpoint, args.output))
    except OSError as error:
        print(f"pool write failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
