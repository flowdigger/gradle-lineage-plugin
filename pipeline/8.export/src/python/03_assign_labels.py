#!/usr/bin/env python3

"""
03_assign_labels.py
Pipeline-friendly version.
"""

import argparse
import json
import re
import sys
from collections import Counter, defaultdict

DOMAIN_KEYWORDS = {
    "Counterparty": ["customer","client","counterparty","party","borrower","obligor"],
    "Collateral": ["collateral","cover","guarantee","pledge"],
    "Exposure": ["exposure","facility","contract","loan","limit"],
    "Rating": ["rating","grade","scorecard"],
    "PD": ["pd","probability"],
    "LGD": ["lgd","loss"],
    "EAD": ["ead"],
    "RWA": ["rwa","capital","basel"],
    "IFRS9": ["ifrs9","ecl","impairment","provision"],
    "Reporting": ["report","dashboard","mart","summary"],
}


def tokenize(text):
    text = re.sub(r'([a-z])([A-Z])', r'\\1_\\2', text)
    text = re.sub(r'[^A-Za-z0-9]', '_', text)
    return {t.lower() for t in text.split('_') if t}


def determine_stage(node):
    xppr = node.get('xppr', 0.5)
    if xppr < 0.20:
        return 'Source'
    if xppr < 0.40:
        return 'Preprocessing'
    if xppr < 0.70:
        return 'Calculation'
    if xppr < 0.90:
        return 'Aggregation'
    return 'Reporting'


def determine_cluster_domains(nodes):
    cluster_tokens = defaultdict(Counter)

    for node in nodes:
        cluster = node.get('cluster', -1)
        for token in tokenize(node.get('label', '')):
            cluster_tokens[cluster][token] += 1

    cluster_domains = {}

    for cluster, token_counts in cluster_tokens.items():
        cluster_words = set(token_counts.keys())
        best_domain = 'Unknown'
        best_score = 0

        for domain, keywords in DOMAIN_KEYWORDS.items():
            score = len(cluster_words & set(keywords))
            if score > best_score:
                best_score = score
                best_domain = domain

        cluster_domains[cluster] = best_domain

    return cluster_domains


def create_business_label(category, domain, stage):
    parts = []
    if category:
        parts.append(category)
    if domain and domain != 'Unknown':
        parts.append(domain)
    if stage:
        parts.append(stage)
    return ' '.join(parts)


def process(graph):
    nodes = graph.get('nodes', [])

    if not nodes:
        # raise ValueError("Graph must have 'nodes'.")
        return graph

    cluster_domains = determine_cluster_domains(nodes)

    for node in nodes:
        cluster = node.get('cluster', -1)
        domain = cluster_domains.get(cluster, 'Unknown')
        stage = determine_stage(node)
        category = node.get('dominant_category', node.get('seed_category', 'Unknown'))

        node['domain'] = domain
        node['stage'] = stage
        node['business_label'] = create_business_label(category, domain, stage)

    return graph


def parse_args():
    parser = argparse.ArgumentParser(description='Assign business labels to nodes')
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
