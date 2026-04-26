#!/usr/bin/env python3
"""Reproject GeoJSON coordinates from one CRS to another.

Usage:
    python reproject_geojson.py <input> <output> [--from-crs EPSG:27700] [--to-crs EPSG:4326]
"""

import argparse
import json
import sys
from pyproj import Transformer


def transform_coords(coords, transformer):
    if not coords:
        return coords
    if isinstance(coords[0], (int, float)):
        x, y = transformer.transform(coords[0], coords[1])
        return [x, y] + list(coords[2:])
    return [transform_coords(c, transformer) for c in coords]


def transform_geometry(geometry, transformer):
    if geometry is None:
        return None
    if geometry["type"] == "GeometryCollection":
        geometry["geometries"] = [transform_geometry(g, transformer) for g in geometry["geometries"]]
    else:
        geometry["coordinates"] = transform_coords(geometry["coordinates"], transformer)
    return geometry


def main():
    parser = argparse.ArgumentParser(description="Reproject GeoJSON coordinates between CRS.")
    parser.add_argument("input", help="Input GeoJSON file path")
    parser.add_argument("output", help="Output GeoJSON file path")
    parser.add_argument("--from-crs", default="EPSG:27700", help="Source CRS (default: EPSG:27700)")
    parser.add_argument("--to-crs", default="EPSG:4326", help="Target CRS (default: EPSG:4326)")
    args = parser.parse_args()

    transformer = Transformer.from_crs(args.from_crs, args.to_crs, always_xy=True)

    print(f"Reading {args.input}...")
    with open(args.input, "r", encoding="utf-8") as f:
        data = json.load(f)

    geotype = data.get("type")
    if geotype == "FeatureCollection":
        for feature in data.get("features", []):
            transform_geometry(feature.get("geometry"), transformer)
    elif geotype == "Feature":
        transform_geometry(data.get("geometry"), transformer)
    else:
        transform_geometry(data, transformer)

    to_epsg = args.to_crs.replace("EPSG:", "").replace("epsg:", "")
    if "crs" in data:
        data["crs"] = {
            "type": "name",
            "properties": {"name": f"urn:ogc:def:crs:EPSG::{to_epsg}"},
        }

    print(f"Writing {args.output}...")
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, separators=(",", ":"))

    print(f"Done. {args.from_crs} → {args.to_crs}")


if __name__ == "__main__":
    main()
