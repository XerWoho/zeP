#!/usr/bin/env python3
import argparse
import json
import os
import hashlib
import datetime

BASE_PATH = "zep.run/releases"
JSON_PATH = "zep.run/download.json"


def sha256_of(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()


def parse_target(filename, version):
    # ex: zep_x86-windows_0.6.zip
    #     zep_<target>_<version>.zip or .tar.xz
    name = filename.replace(f"_{version}", "")
    name = name.replace("zep_", "")
    name = name.split(".")[0]
    return name

def version_key(v: str):
    try:
        # Convert "0.7" → (0, 7)
        return tuple(int(x) for x in v.split('.'))
    except:
        # Non-numeric versions (like "master") go last in sorting,
        # but since we manually reinsert master at top, this is fine.
        return (999999,)

def sort_versions(data: dict):
    master_value = data.get("master")

    # Extract numeric versions
    numeric = {k: v for k, v in data.items() if k != "master"}

    # Sort ascending by numeric order
    sorted_numeric = dict(sorted(numeric.items(), key=lambda x: version_key(x[0]), reverse=True))

    # Rebuild final dict with master at top
    new_data = {}
    if master_value is not None:
        new_data["master"] = master_value

    new_data.update(sorted_numeric)
    return new_data

def load_json():
    if not os.path.exists(JSON_PATH):
        return {}

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def save_json(data):
    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)


def ensure_entry(data, version):
    if version not in data:
        data[version] = {
            "version": version,
            "date": datetime.date.today().isoformat(),
            "docs": "https://github.com/XerWoho/zeP/tree/main/docs"
        }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True, help="Version to process, e.g. 0.7")
    args = parser.parse_args()

    version = args.version
    release_path = os.path.join(BASE_PATH, version)

    if not os.path.isdir(release_path):
        print(f"ERROR: Release folder '{release_path}' does not exist.")
        return 1

    data = load_json()
    # clear master, as we update master with the "new" release
    data["master"] = {}
    ensure_entry(data, version)

    files = os.listdir(release_path)

    for file_name in files:
        if not file_name.startswith("zep_"):
            continue

        full_path = os.path.join(release_path, file_name)
        size = os.path.getsize(full_path)
        checksum = sha256_of(full_path)
        target = parse_target(file_name, version)

        url = f"https://zep.run/releases/{version}/{file_name}"

        entry = {
            "tarball": url,
            "sha256sum": checksum,
            "size": str(size)
        }

        # write into <version>
        data[version][target] = entry

    data["master"] = data[version]

    data = sort_versions(data)
    save_json(data)
    print(f"Updated download.json for version {version}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
