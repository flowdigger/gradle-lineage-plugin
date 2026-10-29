#!/usr/bin/env python3

"""
05_remove_labels.py
Pipeline-friendly version.
"""

import argparse
import json
import sys
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

def load_labels_to_remove(path: Path) -> set[str]:
    # if path is None:
    path = SCRIPT_DIR / "remove_node_labels.txt"
    labels = set()
    with open(path, 'r', encoding='utf-8') as f:
        for raw in f:
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            labels.add(line)
    return labels


def remove_node_labels(graph: dict, labels_to_remove: set[str]) -> tuple[int, int]:
    nodes = graph.get('nodes', [])
    nodes_touched = 0
    keys_removed = 0

    for node in nodes:
        removed_here = 0
        for key in labels_to_remove:
            if key in node:
                node.pop(key, None)
                removed_here += 1

        if removed_here:
            nodes_touched += 1
            keys_removed += removed_here

    return nodes_touched, keys_removed


def process(graph: dict, labels_to_remove: set[str]) -> dict:
    remove_node_labels(graph, labels_to_remove)
    return graph


def parse_args():
    parser = argparse.ArgumentParser(description='Remove selected node labels')
    parser.add_argument('--labels-file', default='remove_node_labels.txt')
    parser.add_argument('-i', '--input')
    parser.add_argument('-o', '--output')
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    labels_path = Path(args.labels_file)
    labels_to_remove = load_labels_to_remove(labels_path)

    input_handle = open(args.input, 'r', encoding='utf-8') if args.input else sys.stdin

    try:
        graph = json.load(input_handle)
    finally:
        if args.input:
            input_handle.close()

    graph = process(graph, labels_to_remove)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as output_handle:
            json.dump(graph, output_handle, indent=2)
    else:
        json.dump(graph, sys.stdout, indent=2)

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
