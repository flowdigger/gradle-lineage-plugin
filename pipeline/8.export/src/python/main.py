#!/usr/bin/env python3

import argparse
import importlib.util
import json
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent

def load_module(module_path):
    module_file = SCRIPT_DIR / module_path
    module_name = Path(module_path).stem.replace('-', '_')
    spec = importlib.util.spec_from_file_location(module_name, module_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

seed_categories = load_module('01_seed_categories.py')
seed_components = load_module('02_seed_components.py')
assign_labels = load_module('03_assign_labels.py')
propagate_categories = load_module('04_propagate_categories.py')
remove_labels = load_module('05_remove_labels.py')


def convert(graph, labels_to_remove):
    graph = seed_categories.process(graph)
    graph = seed_components.process(graph)
    graph = assign_labels.process(graph)
    graph = propagate_categories.process(graph)
    graph = remove_labels.process(graph, labels_to_remove)
    return graph


def main():
    parser = argparse.ArgumentParser()

    parser.add_argument('input_dir')
    parser.add_argument('output_dir')
    parser.add_argument(
        '--labels-file',
        default='remove_node_labels.txt',
        help='Text file containing node properties to remove'
    )

    args = parser.parse_args()

    input_dir = Path(args.input_dir)
    output_dir = Path(args.output_dir)

    output_dir.mkdir(parents=True, exist_ok=True)

    labels_to_remove = remove_labels.load_labels_to_remove(
        Path(args.labels_file)
    )

    for infile in sorted(input_dir.glob('*.json')):
        outfile = output_dir / infile.name

        with open(infile, 'r', encoding='utf-8') as fin:
            payload = fin.read().strip()

        if not payload:
            print(f'Skipping empty JSON file: {infile}')
            continue

        try:
            graph = json.loads(payload)
        except json.JSONDecodeError as exc:
            print(f'Skipping invalid JSON file {infile}: {exc}')
            continue

        graph = convert(graph, labels_to_remove)

        with open(outfile, 'w', encoding='utf-8') as fout:
            json.dump(graph, fout, indent=2, ensure_ascii=False)

        print(f'Converted {infile} -> {outfile}')

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
