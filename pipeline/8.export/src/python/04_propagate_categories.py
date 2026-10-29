#!/usr/bin/env python3

"""
04_propagate_categories.py
Pipeline-friendly version.
"""

import argparse
import json
import sys
from collections import defaultdict

MAX_ITERATIONS = 10
DECAY = 0.85


def build_indexes(nodes, edges):
    node_map = {n['id']: n for n in nodes}
    parents = defaultdict(set)
    children = defaultdict(set)

    for edge in edges:
        src = edge['source']
        tgt = edge['target']
        parents[tgt].add(src)
        children[src].add(tgt)

    return node_map, parents, children


def initialize_scores(nodes):
    categories = sorted({n['seed_category'] for n in nodes})

    for node in nodes:
        scores = {c: 0.0 for c in categories}
        scores[node['seed_category']] = node.get('seed_confidence', 1.0)
        node['category_scores'] = scores

    return categories


def propagate(nodes, edges):
    node_map, parents, _ = build_indexes(nodes, edges)
    category_list = initialize_scores(nodes)

    for _ in range(MAX_ITERATIONS):
        new_scores = {}

        for node in nodes:
            node_id = node['id']
            current = node['category_scores'].copy()

            if node_id not in parents:
                new_scores[node_id] = current
                continue

            upstream = parents[node_id]
            accumulated = {c: 0.0 for c in category_list}

            for parent_id in upstream:
                parent = node_map[parent_id]
                for cat, score in parent['category_scores'].items():
                    accumulated[cat] += score * DECAY

            count = max(len(upstream), 1)

            for cat in accumulated:
                accumulated[cat] /= count

            accumulated[node['seed_category']] += node.get('seed_confidence', 0.5)
            new_scores[node_id] = accumulated

        for node in nodes:
            node['category_scores'] = new_scores[node['id']]


def determine_primary_category(node):
    scores = node['category_scores']
    total = sum(scores.values())

    if total == 0:
        return

    normalized = {k: round(v / total, 4) for k, v in scores.items()}

    dominant = max(normalized.items(), key=lambda x: x[1])

    node['category_scores'] = normalized
    node['dominant_category'] = dominant[0]
    node['dominant_score'] = round(dominant[1], 4)
    node['category_blend'] = [
        {'category': k, 'score': v}
        for k, v in sorted(normalized.items(), key=lambda x: x[1], reverse=True)
        if v > 0.05
    ]


def process(graph):
    nodes = graph.get('nodes', [])
    edges = graph.get('edges', [])

    if not nodes or not edges:
        # raise ValueError("Graph must have 'nodes' and 'edges'.")
        return graph

    propagate(nodes, edges)

    for node in nodes:
        determine_primary_category(node)

    return graph


def parse_args():
    parser = argparse.ArgumentParser(description='Propagate categories through graph')
    parser.add_argument('-i', '--input')
    parser.add_argument('-o', '--output')
    return parser.parse_args()


def main():
    args = parse_args()

    input_handle = open(args.input, 'r', encoding='utf-8') if args.input else sys.stdin

    try:
        graph = json.load(input_handle)
    finally:
        if args.input:
            input_handle.close()

    graph = process(graph)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as output_handle:
            json.dump(graph, output_handle, indent=2)
    else:
        json.dump(graph, sys.stdout, indent=2)

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
