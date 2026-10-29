#!/usr/bin/env python3
"""
01_seed_categories.py
Refactored version exposing process(graph) for in-process pipelines.
"""

import argparse
import json
import re
import sys
from pathlib import Path
import yaml

CONFIG_FILE = "category_config.yaml"


def load_config():
    with open(CONFIG_FILE, "r", encoding="utf-8") as f:
        return yaml.safe_load(f)


CONFIG = load_config() if Path(CONFIG_FILE).exists() else {}
KEYWORDS = {}
SUBCATEGORIES = CONFIG.get("subcategories", {}) if CONFIG else {}
RULES = sorted(CONFIG.get("rules", []), key=lambda r: r.get("priority", 0), reverse=True) if CONFIG else []


def tokenize_name(name):
    if not name:
        return set()
    name = re.sub(r'([a-z])([A-Z])', r'\1_\2', name)
    name = re.sub(r'[^A-Za-z0-9]', '_', name)
    return {t.lower() for t in name.split('_') if t}


def normalize_name(name):
    if not name:
        return ''
    name = re.sub(r'([a-z])([A-Z])', r'\1_\2', name)
    name = re.sub(r'[^A-Za-z0-9]', '_', name)
    return re.sub(r'_+', '_', name).strip('_').lower()


def apply_rules(table_name):
    table_name = table_name.lower()
    for rule in RULES:
        category = rule.get('category')
        for text in rule.get('match', {}).get('contains', []):
            if text.lower() in table_name:
                return category, rule.get('name', 'rule')
    return None, None


def determine_category(table_name):
    category, rule_name = apply_rules(table_name)
    if category:
        return {
            'category': category,
            'subcategory': SUBCATEGORIES.get(category, category),
            'confidence': 1.0,
            'classification_source': rule_name,
            'keyword_matches': 0,
        }
    return {
        'category': 'Unknown',
        'subcategory': 'Unknown',
        'confidence': 0.0,
        'classification_source': 'unknown',
        'keyword_matches': 0,
    }


def detect_sources_and_sinks(nodes, edges):
    incoming = {n['id']: 0 for n in nodes}
    outgoing = {n['id']: 0 for n in nodes}
    for edge in edges:
        if edge['source'] in outgoing:
            outgoing[edge['source']] += 1
        if edge['target'] in incoming:
            incoming[edge['target']] += 1
    return (
        {k for k, v in incoming.items() if v == 0},
        {k for k, v in outgoing.items() if v == 0},
    )


def process(graph):
    nodes = graph.get('nodes', [])
    edges = graph.get('edges', [])
    sources, sinks = detect_sources_and_sinks(nodes, edges)

    for node in nodes:
        result = determine_category(node.get('label', node['id']))
        node['is_source'] = node['id'] in sources
        node['is_sink'] = node['id'] in sinks
        node['seed_category'] = result['category']
        node['seed_subcategory'] = result['subcategory']
        node['seed_confidence'] = result['confidence']
        node['classification_source'] = result['classification_source']
        node['keyword_matches'] = result['keyword_matches']

    return graph


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('-i', '--input')
    p.add_argument('-o', '--output')
    return p.parse_args()


def main():
    args = parse_args()

    input_handle = open(args.input, encoding='utf-8') if args.input else sys.stdin
    output_handle = open(args.output, 'w', encoding='utf-8') if args.output else sys.stdout

    try:
        graph = json.load(input_handle)
        json.dump(process(graph), output_handle, indent=2)
        return 0
    finally:
        if args.input:
            input_handle.close()
        if args.output:
            output_handle.close()


if __name__ == '__main__':
    raise SystemExit(main())
