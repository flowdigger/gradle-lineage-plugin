#!/usr/bin/env python3

"""
02_seed_components.py

Pipeline-friendly version.
Exposes process(graph) so it can be imported and chained:

    from seed_categories import process as process1
    from seed_components import process as process2

    graph = process1(graph)
    graph = process2(graph)
"""

from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Seed connected_component_id into graph nodes"
    )
    parser.add_argument("-i", "--input")
    parser.add_argument("-o", "--output")
    parser.add_argument("--glob")
    parser.add_argument("--suffix", default="_components")
    return parser.parse_args()


def get_edges_array(graph: dict[str, Any]) -> tuple[list[dict[str, Any]], str]:
    if isinstance(graph.get("edges"), list):
        return graph["edges"], "edges"
    if isinstance(graph.get("links"), list):
        return graph["links"], "links"
    raise ValueError("Graph JSON must contain an array under 'edges' or 'links'.")


def build_undirected_adjacency(node_ids: set[str], edges: list[dict[str, Any]]) -> dict[str, set[str]]:
    adjacency = {node_id: set() for node_id in node_ids}
    for edge in edges:
        source = edge.get("source")
        target = edge.get("target")
        if isinstance(source, str) and isinstance(target, str):
            if source in adjacency and target in adjacency:
                adjacency[source].add(target)
                adjacency[target].add(source)
    return adjacency


def detect_connected_components(node_ids: set[str], adjacency: dict[str, set[str]]) -> dict[str, int]:
    visited = set()
    component_index = 0
    node_to_component = {}

    for root in sorted(node_ids):
        if root in visited:
            continue

        queue = deque([root])
        while queue:
            node_id = queue.popleft()
            if node_id in visited:
                continue

            visited.add(node_id)
            node_to_component[node_id] = component_index

            for neighbor in sorted(adjacency[node_id]):
                if neighbor not in visited:
                    queue.append(neighbor)

        component_index += 1

    return node_to_component


def annotate_graph(graph: dict[str, Any]) -> tuple[dict[str, Any], dict[str, int]]:
    raw_nodes = graph.get("nodes")
    if not isinstance(raw_nodes, list):
        raise ValueError("Graph JSON must contain a 'nodes' array.")

    edges, _ = get_edges_array(graph)

    node_ids = {
        node["id"]
        for node in raw_nodes
        if isinstance(node, dict) and isinstance(node.get("id"), str)
    }

    adjacency = build_undirected_adjacency(node_ids, edges)
    node_to_component = detect_connected_components(node_ids, adjacency)

    component_sizes = {}

    for node in raw_nodes:
        node_id = node.get("id")
        if not isinstance(node_id, str):
            continue

        component_id = node_to_component.get(node_id, -1)
        node["connected_component_id"] = component_id
        component_sizes[component_id] = component_sizes.get(component_id, 0) + 1

    metadata = graph.setdefault("metadata", {})
    metadata["connected_component_count"] = len(component_sizes)
    metadata["largest_connected_component_size"] = max(component_sizes.values()) if component_sizes else 0

    stats = {
        "node_count": len(node_ids),
        "edge_count": len(edges),
        "component_count": len(component_sizes),
        "largest_component_size": max(component_sizes.values()) if component_sizes else 0,
    }

    return graph, stats


def process(graph: dict[str, Any]) -> dict[str, Any]:
    graph, _ = annotate_graph(graph)
    return graph


def main() -> int:
    import sys

    args = parse_args()

    if args.input:
        with open(args.input, 'r', encoding='utf-8') as f:
            graph = json.load(f)
    else:
        graph = json.load(sys.stdin)

    graph = process(graph)

    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            json.dump(graph, f, indent=2)
    else:
        json.dump(graph, sys.stdout, indent=2)

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
