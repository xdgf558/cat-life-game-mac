#!/usr/bin/env python3
"""Fail before generation/build when required runtime media are absent or LFS pointers."""
from __future__ import annotations

import argparse
from dataclasses import dataclass
from enum import Enum
import json
import sys
from pathlib import Path


LFS_HEADER = b"version https://git-lfs.github.com/spec/v1"
RUNTIME_DIRECTORIES = ("CatLife/Assets.xcassets", "CatLife/Audio", "CatLifeMac/Assets.xcassets")
MANIFEST = "scripts/runtime_assets.json"
SANDBOX_INPUTS = "scripts/runtime_assets.xcfilelist"
DOWNLOAD_COMMAND = 'git lfs pull --include="CatLife/**,CatLifeMac/**"'


class Recovery(Enum):
    DOWNLOAD = "download"
    RESTORE = "restore"
    INVENTORY = "inventory"
    ACCESS = "access"


@dataclass(frozen=True)
class Problem:
    message: str
    recovery: Recovery


def validate_media(path: Path) -> Problem | None:
    if not path.is_file():
        return Problem("missing runtime resource", Recovery.DOWNLOAD)
    try:
        with path.open("rb") as stream:
            header = stream.read(256)
    except OSError:
        return Problem("unreadable runtime resource; check file access permissions", Recovery.ACCESS)
    if header.startswith(LFS_HEADER):
        return Problem("Git LFS pointer; the media has not been downloaded", Recovery.DOWNLOAD)
    if not header:
        return Problem("empty runtime resource", Recovery.RESTORE)
    # This is an early hydration/header check, not an image or audio decoder.
    suffix = path.suffix.lower()
    if suffix == ".png" and (len(header) < 24 or not header.startswith(b"\x89PNG\r\n\x1a\n")):
        return Problem("invalid or truncated PNG header", Recovery.RESTORE)
    if suffix in (".jpg", ".jpeg") and not header.startswith(b"\xff\xd8\xff"):
        return Problem("invalid JPEG header", Recovery.RESTORE)
    if suffix == ".caf" and (len(header) < 8 or not header.startswith(b"caff\x00\x01")):
        return Problem("invalid or truncated CAF header", Recovery.RESTORE)
    return None


def relative_resource(value: object) -> str:
    if not isinstance(value, str):
        raise ValueError("resource paths must be strings")
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or not any(
        value.startswith(directory + "/") for directory in RUNTIME_DIRECTORIES
    ):
        raise ValueError("resource path is outside the runtime directories")
    return value


def sandbox_inputs(root: Path, resources: list[str]) -> list[str]:
    # Directory inputs alone do not authorize opening descendant file contents.
    inputs = set(resources)
    for directory in RUNTIME_DIRECTORIES:
        inputs.add(directory)
        inputs.update(path.relative_to(root).as_posix()
                      for path in (root / directory).rglob("*")
                      if not path.name.startswith("."))
    return ["$(SRCROOT)/" + path for path in sorted(inputs)]


def inspect(root: Path, *, updating_manifest: bool = False) -> tuple[list[str], list[Problem]]:
    errors: list[Problem] = []
    required: set[str] = set()
    inventoried: set[str] | None = None
    if not updating_manifest:
        try:
            manifest = json.loads((root / MANIFEST).read_text())
            entries = manifest["resources"]
            if manifest.get("schemaVersion") != 1 or not isinstance(entries, list) or not entries:
                raise ValueError("expected a nonempty schema 1 resource list")
            inventoried = {relative_resource(item) for item in entries}
            required.update(inventoried)
        except (OSError, ValueError, KeyError, TypeError) as error:
            errors.append(Problem(f"{MANIFEST}: invalid or missing runtime inventory ({type(error).__name__})", Recovery.INVENTORY))

    for directory in RUNTIME_DIRECTORIES:
        if not (root / directory).is_dir():
            errors.append(Problem(f"{directory}: missing runtime directory", Recovery.DOWNLOAD))
    catalog = root / RUNTIME_DIRECTORIES[0]
    for metadata in (catalog / "Contents.json", catalog / "AppIcon.appiconset/Contents.json"):
        if not metadata.is_file():
            errors.append(Problem(f"{metadata.relative_to(root).as_posix()}: missing asset catalog metadata", Recovery.RESTORE))
    # Include every declared catalog file, including newly added assets which
    # have not yet been added to the inventory. The inventory also catches a
    # whole imageset/audio file being deleted, which a directory scan cannot.
    for metadata in sorted(list(catalog.rglob("Contents.json")) + list((root / "CatLifeMac/Assets.xcassets").rglob("Contents.json"))):
        try:
            content = json.loads(metadata.read_text())
            for collection in ("images", "data"):
                for item in content.get(collection, []):
                    filename = item.get("filename")
                    if filename is None:
                        continue
                    if not isinstance(filename, str) or Path(filename).name != filename:
                        raise ValueError("asset filenames must be simple relative names")
                    required.add(relative_resource((metadata.parent / filename).relative_to(root).as_posix()))
        except (OSError, ValueError, TypeError, AttributeError) as error:
            errors.append(Problem(f"{metadata.relative_to(root).as_posix()}: invalid catalog metadata ({type(error).__name__})", Recovery.RESTORE))
    for directory in RUNTIME_DIRECTORIES:
        required.update(path.relative_to(root).as_posix() for path in (root / directory).rglob("*")
                        if path.is_file() and path.name != "Contents.json" and not path.name.startswith("."))
    if not required:
        errors.append(Problem("runtime resource inventory is empty", Recovery.INVENTORY))
    for relative in sorted(required):
        problem = validate_media(root / relative)
        if problem:
            errors.append(Problem(f"{relative}: {problem.message}", problem.recovery))
    resources = sorted(required)
    if not updating_manifest:
        if inventoried is not None and required != inventoried:
            errors.append(Problem(f"{MANIFEST}: stale runtime inventory; resources have changed", Recovery.INVENTORY))
        try:
            declared = (root / SANDBOX_INPUTS).read_text().splitlines()
            if declared != sandbox_inputs(root, resources):
                errors.append(Problem(f"{SANDBOX_INPUTS}: stale sandbox input list; resources or metadata have changed", Recovery.INVENTORY))
        except (OSError, UnicodeError) as error:
            errors.append(Problem(f"{SANDBOX_INPUTS}: missing or unreadable sandbox input list ({type(error).__name__}); check file access permissions", Recovery.INVENTORY))
    return resources, errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent,
                        help="Mac repository root (defaults to the script's parent)")
    parser.add_argument("--update-manifest", action="store_true",
                        help="record a deliberate runtime asset addition/removal after validating all present media")
    args = parser.parse_args(argv)
    resources, errors = inspect(args.root, updating_manifest=args.update_manifest)
    if errors:
        print("error: CatLife runtime assets are not ready; generation/build stopped.", file=sys.stderr)
        for error in errors:
            print(f"error: {error.message}", file=sys.stderr)
        recoveries = {error.recovery for error in errors}
        if Recovery.DOWNLOAD in recoveries:
            print("error: For missing media or Git LFS pointers, run from the repository root:", file=sys.stderr)
            print("error:   git lfs install", file=sys.stderr)
            print(f"error:   {DOWNLOAD_COMMAND}", file=sys.stderr)
        if Recovery.INVENTORY in recoveries:
            print("error: Restore runtime_assets.json/runtime_assets.xcfilelist from Git; check permissions if unreadable.", file=sys.stderr)
            print("error: After deliberate resource changes, regenerate both lists with:", file=sys.stderr)
            print("error:   python3 -B scripts/check_runtime_assets.py --update-manifest", file=sys.stderr)
        if Recovery.ACCESS in recoveries:
            print("error: Check read permissions and Xcode script sandbox inputs for the unreadable resources.", file=sys.stderr)
        if Recovery.RESTORE in recoveries or Recovery.DOWNLOAD in recoveries:
            print("error: Restore locally deleted or invalid resource/metadata files from Git.", file=sys.stderr)
        print("error: Re-run python3 scripts/check_runtime_assets.py before building.", file=sys.stderr)
        return 1
    if args.update_manifest:
        (args.root / MANIFEST).write_text(json.dumps({"schemaVersion": 1, "resources": resources}, indent=2) + "\n")
        (args.root / SANDBOX_INPUTS).write_text("\n".join(sandbox_inputs(args.root, resources)) + "\n")
    print(f"CatLife runtime asset preflight passed: {len(resources)} hydrated files.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
