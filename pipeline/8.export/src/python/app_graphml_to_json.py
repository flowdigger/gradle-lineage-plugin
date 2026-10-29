#!/usr/bin/env python3
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"g": "http://graphml.graphdrawing.org/xmlns"}


def parse_graphml(path: Path) -> dict:
    tree = ET.parse(path)
    root = tree.getroot()
    graph = root.find("g:graph", NS)
    if graph is None:
        return {"schema": "uniform-app", "processor": path.stem, "nodes": [], "edges": [], "meta": {"nodeCount": 0, "edgeCount": 0}}

    processor = path.stem
    processor_data = graph.find("g:data[@key='processor']", NS)
    if processor_data is not None and processor_data.text:
        processor = processor_data.text.strip()

    nodes = []
    for node in graph.findall("g:node", NS):
        node_id = (node.get("id") or "").strip()
        if not node_id:
            continue
        nodes.append({"id": node_id, "label": node_id, "type": "entity"})

    edges = []
    for edge in graph.findall("g:edge", NS):
        edge_id = (edge.get("id") or "").strip()
        source = (edge.get("source") or "").strip()
        target = (edge.get("target") or "").strip()
        if not source or not target:
            continue
        edge_payload = {
            "id": edge_id or f"edge-{len(edges)+1}",
            "source": source,
            "target": target,
            "label": "",
            "size": 1,
        }
        for data in edge.findall("g:data", NS):
            key = data.get("key")
            value = (data.text or "").strip()
            if key == "procedure":
                edge_payload["label"] = value
            elif key == "database":
                edge_payload["database"] = value
        edges.append(edge_payload)

    return {
        "schema": "uniform-app",
        "processor": processor,
        "nodes": nodes,
        "edges": edges,
        "meta": {"nodeCount": len(nodes), "edgeCount": len(edges)},
    }


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: app_graphml_to_json.py <graphml-dir> <json-dir>", file=sys.stderr)
        return 2

    graphml_dir = Path(sys.argv[1]).resolve()
    json_dir = Path(sys.argv[2]).resolve()
    json_dir.mkdir(parents=True, exist_ok=True)

    for graphml_file in sorted(graphml_dir.glob("*.graphml")):
        payload = parse_graphml(graphml_file)
        out_file = json_dir / f"{graphml_file.stem}.json"
        with out_file.open("w", encoding="utf-8") as f:
            json.dump(payload, f, indent=2, ensure_ascii=True)
            f.write("\n")
        print(f"[SUCCESS] {graphml_file} -> {out_file}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
