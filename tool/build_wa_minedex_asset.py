#!/usr/bin/env python3
"""Build the compact, offline WA MINEDEX operator/worksite catalogue.

Inputs are official CC BY 4.0 MINEDEX CSV exports and the ABS 2021 Postal
Areas shapefile. Raw downloads are deliberately not bundled in the app.
"""

import argparse
import csv
import json
import re
import zipfile
from collections import defaultdict
from pathlib import Path

import shapefile


ALLOWED_STAGES = {"Operating", "Under Development", "Proposed", "Care and Maintenance"}


def clean(value):
    return (value or "").strip()


def valid_operator(name):
    upper = name.upper()
    return bool(name) and not any(x in upper for x in ("TEST", "UNKNOWN", "DUMMY", "N/A"))


def point_in_ring(x, y, points):
    inside = False
    j = len(points) - 1
    for i, (xi, yi) in enumerate(points):
        xj, yj = points[j]
        if ((yi > y) != (yj > y)) and x < (xj - xi) * (y - yi) / ((yj - yi) or 1e-30) + xi:
            inside = not inside
        j = i
    return inside


def point_in_shape(x, y, shape):
    if not hasattr(shape, "bbox"):
        return False
    minx, miny, maxx, maxy = shape.bbox
    if not (minx <= x <= maxx and miny <= y <= maxy):
        return False
    parts = list(shape.parts) + [len(shape.points)]
    # Even/odd across rings handles holes as well as multipart polygons.
    inside = False
    for start, end in zip(parts, parts[1:]):
        if point_in_ring(x, y, shape.points[start:end]):
            inside = not inside
    return inside


def postcode_lookup(zip_path):
    extract_dir = zip_path.parent / "poa_shape"
    extract_dir.mkdir(exist_ok=True)
    with zipfile.ZipFile(zip_path) as archive:
        archive.extractall(extract_dir)
    shp = next(extract_dir.glob("*.shp"))
    reader = shapefile.Reader(str(shp))
    field_names = [f[0] for f in reader.fields[1:]]
    code_index = field_names.index("POA_CODE21")
    shapes = [(sr.record[code_index], sr.shape) for sr in reader.iterShapeRecords()]

    def find(longitude, latitude):
        for postcode, shape in shapes:
            if point_in_shape(longitude, latitude, shape):
                return str(postcode)
        return ""

    return find


def category(site):
    haystack = " ".join(clean(site.get(k)).lower() for k in ("SITE_TYPE", "SUB_TYPE", "COMMODITIES", "COMMODITY_GROUP_NAME"))
    if any(x in haystack for x in ("petroleum", "oil", "gas", "lng")):
        return "oil_gas_energy"
    if any(x in haystack for x in ("wind", "solar", "renewable")):
        return "renewables"
    return "mining_company"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--operating", type=Path, required=True)
    parser.add_argument("--major", type=Path, required=True)
    parser.add_argument("--operators", type=Path, required=True)
    parser.add_argument("--poa-zip", type=Path, required=True)
    parser.add_argument("--regional-json", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    sites = {}
    for path in (args.operating, args.major):
        with path.open(encoding="utf-8-sig", newline="") as handle:
            for row in csv.DictReader(handle):
                code = clean(row.get("SITE_CODE"))
                if code and clean(row.get("STAGE")) in ALLOWED_STAGES:
                    sites[code] = row

    current_by_site = defaultdict(list)
    with args.operators.open(encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            if clean(row.get("OP_END")) or clean(row.get("SITE_STAGE")) not in ALLOWED_STAGES:
                continue
            if valid_operator(clean(row.get("OP_NAME"))):
                current_by_site[clean(row.get("SITE_CODE"))].append(row)

    find_postcode = postcode_lookup(args.poa_zip)
    regional_doc = json.loads(args.regional_json.read_text())
    regional = {
        str(p).zfill(4)
        for item in regional_doc
        if "regional australia" in str(item.get("industry", item.get("id", ""))).lower()
        for p in item.get("postcodes", [])
    }

    records = []
    for site_code, site in sorted(sites.items()):
        operators = current_by_site.get(site_code, [])
        if not operators:
            continue
        operators.sort(key=lambda r: (bool(clean(r.get("OP_EMAIL")) or clean(r.get("OP_PHONE"))), clean(r.get("OP_START"))), reverse=True)
        op = operators[0]
        try:
            longitude = float(clean(site.get("LONGITUDE")))
            latitude = float(clean(site.get("LATITUDE")))
        except ValueError:
            continue
        postcode = find_postcode(longitude, latitude)
        operator_code = clean(op.get("OP_CODE"))
        name = clean(op.get("OP_NAME"))
        worksite = clean(site.get("TITLE")) or clean(site.get("SHORT_TITLE")) or clean(op.get("SITE_NAME"))
        identifier = re.sub(r"[^a-z0-9]+", "_", f"{site_code}_{operator_code}".lower()).strip("_")
        phone = clean(op.get("OP_PHONE"))
        email = clean(op.get("OP_EMAIL"))
        records.append({
            "id": f"wa_minedex_{identifier}", "docId": f"wa_minedex_{identifier}",
            "name": name, "worksite_name": worksite, "site_code": site_code,
            "project_code": clean(site.get("PROJ_CODE")), "operator_code": operator_code,
            "operator_names": sorted({clean(x.get("OP_NAME")) for x in operators}),
            "latitude": latitude, "longitude": longitude, "postcode": postcode,
            "postcode_display": postcode, "state": "WA", "phone": phone,
            "email": email, "address": clean(op.get("OP_ADDRESS")),
            "construction_category": category(site), "entity_kind": "employer",
            "classification_confidence": 100,
            "classification_reason": "Current operator linked to an official MINEDEX worksite by SITE_CODE",
            "classification_source": "wa_minedex_official_join",
            "relationship_role": "current_operator", "location_role": "worksite",
            "worksite_stage": clean(site.get("STAGE")), "commodities": clean(site.get("COMMODITIES")),
            "development_region": clean(site.get("DEVELOPMENT_REGION")),
            "regional_work_eligible": postcode in regional,
            "source": "wa_minedex_site_operator", "source_place_id": f"minedex:{site_code}:{operator_code}",
            "catalog_sources": ["wa_minedex_operating_or_major", "wa_minedex_site_operators", "abs_poa_2021"],
            "source_extract_date": clean(site.get("EXTRACT_DATE")) or clean(op.get("EXTRACT_DA")),
            "source_url": "https://dasc.dmirs.wa.gov.au/", "source_license": "CC BY 4.0",
            "source_attribution": "Attribution: Based on Department of Mines, Petroleum and Exploration material",
            "postcode_source": "ABS Postal Areas 2021 (statistical approximation)",
            "has_public_contact": bool(phone or email),
            "contact_enrichment_status": "pending",
            "official_contact_fields": [field for field, value in (("phone", phone), ("email", email), ("address", clean(op.get("OP_ADDRESS")))) if value],
        })

    payload = {
        "schema_version": 1,
        "generated_from": "Official MINEDEX and ABS open-data downloads",
        "license": "MINEDEX CC BY 4.0; ABS attribution applies",
        "records": records,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, separators=(",", ":")))
    print(json.dumps({"records": len(records), "with_contact": sum(r["has_public_contact"] for r in records), "regional": sum(r["regional_work_eligible"] for r in records)}))


if __name__ == "__main__":
    main()
