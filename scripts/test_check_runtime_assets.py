#!/usr/bin/env python3
"""Small fixture-only checks; never mutate the app's actual media or Git checkout."""
import contextlib
import io
import json
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET
from unittest.mock import patch
from pathlib import Path

from check_runtime_assets import DOWNLOAD_COMMAND, LFS_HEADER, MANIFEST, SANDBOX_INPUTS, inspect, main, sandbox_inputs


class RuntimeAssetPreflightTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="catlife-asset-preflight-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.png = self.root / "CatLife/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
        self.caf = self.root / "CatLife/Audio/bgm-home.caf"
        self.png.parent.mkdir(parents=True)
        self.caf.parent.mkdir(parents=True)
        (self.root / "scripts").mkdir()
        # Header fixtures are sufficient: the preflight deliberately does not decode media.
        self.png.write_bytes(b"\x89PNG\r\n\x1a\n" + bytes(24))
        self.caf.write_bytes(b"caff\x00\x01\x00\x00" + bytes(24))
        (self.png.parent / "Contents.json").write_text(json.dumps({"images": [{"filename": self.png.name}]}))
        (self.png.parent.parent / "Contents.json").write_text('{"info":{"version":1}}')
        (self.root / MANIFEST).write_text(json.dumps({"schemaVersion": 1, "resources": [
            self.png.relative_to(self.root).as_posix(), self.caf.relative_to(self.root).as_posix()
        ]}))
        self.mac_png = self.root / "CatLifeMac/Assets.xcassets/MacAppIcon.appiconset/MacAppIcon.png"
        self.mac_png.parent.mkdir(parents=True)
        self.mac_png.write_bytes(self.png.read_bytes())
        (self.mac_png.parent / "Contents.json").write_text(json.dumps({"images": [{"filename": self.mac_png.name}]}))
        (self.mac_png.parent.parent / "Contents.json").write_text('{"info":{"version":1}}')
        resources = [self.png.relative_to(self.root).as_posix(), self.caf.relative_to(self.root).as_posix(), self.mac_png.relative_to(self.root).as_posix()]
        (self.root / MANIFEST).write_text(json.dumps({"schemaVersion": 1, "resources": resources}))
        (self.root / SANDBOX_INPUTS).write_text("\n".join(sandbox_inputs(self.root, resources)) + "\n")

    def test_hydrated_resources_pass(self):
        resources, errors = inspect(self.root)
        self.assertEqual(len(resources), 3)
        self.assertEqual(errors, [])

    def test_image_and_audio_pointers_fail_with_download_instructions(self):
        for path in (self.png, self.caf, self.mac_png):
            with self.subTest(path=path.name):
                original = path.read_bytes()
                path.write_bytes(LFS_HEADER + b"\noid sha256:" + b"0" * 64 + b"\nsize 100\n")
                stderr = io.StringIO()
                with contextlib.redirect_stderr(stderr):
                    self.assertEqual(main(["--root", str(self.root)]), 1)
                self.assertIn(path.name, stderr.getvalue())
                self.assertIn("Git LFS pointer", stderr.getvalue())
                self.assertIn(DOWNLOAD_COMMAND, stderr.getvalue())
                path.write_bytes(original)

    def test_missing_image_and_audio_are_reported(self):
        self.png.unlink()
        self.caf.unlink()
        _, errors = inspect(self.root)
        self.assertEqual(sum("missing runtime resource" in value.message for value in errors), 2)

    def test_inventory_catches_an_entire_deleted_imageset(self):
        self.png.unlink()
        (self.png.parent / "Contents.json").unlink()
        self.png.parent.rmdir()
        _, errors = inspect(self.root)
        self.assertTrue(any("AppIcon.png: missing runtime resource" in value.message for value in errors))

    def test_new_catalog_reference_is_checked_before_inventory_refresh(self):
        metadata = self.png.parent / "Contents.json"
        metadata.write_text('{"images":[{"filename":"new-image.png"}]}')
        _, errors = inspect(self.root)
        self.assertTrue(any("new-image.png: missing runtime resource" in value.message for value in errors))

    def test_empty_or_invalid_headers_fail(self):
        self.png.write_bytes(b"")
        self.caf.write_bytes(b"not a CAF")
        _, errors = inspect(self.root)
        self.assertTrue(any("empty runtime resource" in value.message for value in errors))
        self.assertTrue(any("invalid or truncated CAF header" in value.message for value in errors))

    def test_catalog_paths_cannot_escape_runtime_assets(self):
        (self.png.parent / "Contents.json").write_text('{"images":[{"filename":"../../../private.png"}]}')
        _, errors = inspect(self.root)
        self.assertTrue(any("invalid catalog metadata" in value.message for value in errors))

    def test_missing_inventory_fails_without_silently_regenerating_it(self):
        (self.root / MANIFEST).unlink()
        _, errors = inspect(self.root)
        self.assertTrue(any("invalid or missing runtime inventory" in value.message for value in errors))
        self.assertFalse((self.root / MANIFEST).exists())

    def test_explicit_refresh_does_not_record_unhydrated_media(self):
        before = (self.root / MANIFEST).read_bytes()
        self.caf.write_bytes(LFS_HEADER)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(main(["--root", str(self.root), "--update-manifest"]), 1)
        self.assertEqual((self.root / MANIFEST).read_bytes(), before)

    def test_generator_rejects_pointers_before_replacing_an_existing_project(self):
        scripts = Path(__file__).resolve().parent
        for filename in ("generate_project.rb", "check_runtime_assets.py"):
            (self.root / "scripts" / filename).write_bytes((scripts / filename).read_bytes())
        project = self.root / "CatLifeMac.xcodeproj/project.pbxproj"
        project.parent.mkdir()
        project.write_text("existing project must remain untouched\n")
        before = project.read_bytes()
        self.png.write_bytes(LFS_HEADER)
        result = subprocess.run(["ruby", str(self.root / "scripts/generate_project.rb")],
                                capture_output=True, text=True, check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(DOWNLOAD_COMMAND, result.stderr)
        self.assertIn("the Xcode project was not changed", result.stderr)
        self.assertEqual(project.read_bytes(), before)

    def test_generator_is_repeatable_and_source_changes_preserve_existing_object_ids(self):
        scripts = Path(__file__).resolve().parent
        for filename in ("generate_project.rb", "check_runtime_assets.py"):
            (self.root / "scripts" / filename).write_bytes((scripts / filename).read_bytes())
        privacy = "CatLife/PrivacyInfo.xcprivacy"
        (self.root / privacy).write_bytes((scripts.parent / privacy).read_bytes())
        for relative in ("CatLife/A/Shared.swift", "CatLife/B/Shared.swift", "CatLife/ZScene.swift",
                         "CatLifeMacUITests/RoomTests.swift", "CatLifeMacTests/StoreTests.swift"):
            source = self.root / relative
            source.parent.mkdir(parents=True, exist_ok=True)
            source.write_text("// Source-only fixture; no compilation.\n")
        project = self.root / "CatLifeMac.xcodeproj"

        def generate():
            result = subprocess.run(["ruby", str(self.root / "scripts/generate_project.rb")],
                                    capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertNotIn("duplicate UUID", result.stderr)
            return ((project / "project.pbxproj").read_bytes(),
                    (project / "xcshareddata/xcschemes/CatLifeMac.xcscheme").read_bytes())

        def objects():
            result = subprocess.run(["ruby", "-rxcodeproj", "-rjson", "-e",
                                     "puts JSON.generate(Xcodeproj::Project.open(ARGV[0]).to_hash)",
                                     str(project)], capture_output=True, text=True, check=True)
            return json.loads(result.stdout)["objects"]

        baseline = generate()
        self.assertEqual(generate(), baseline)
        original = objects()
        app = next(value for value in original.values()
                   if value["isa"] == "PBXNativeTarget" and value["name"] == "CatLifeMac")
        resources = next(original[identifier] for identifier in app["buildPhases"]
                         if original[identifier]["isa"] == "PBXResourcesBuildPhase")
        resource_paths = [original[original[identifier]["fileRef"]]["path"]
                          for identifier in resources["files"]]
        self.assertEqual(resource_paths.count("PrivacyInfo.xcprivacy"), 1)
        for reference in ET.fromstring(baseline[1]).iter("BuildableReference"):
            self.assertEqual(original[reference.attrib["BlueprintIdentifier"]]["isa"], "PBXNativeTarget")
        for value in original.values():
            if value["isa"] == "PBXContainerItemProxy":
                self.assertEqual(original[value["remoteGlobalIDString"]]["isa"], "PBXNativeTarget")

        for relative in ("CatLife/MFeature.swift", "CatLifeMacUITests/AddedTests.swift", "CatLifeMacTests/AddedTests.swift"):
            with self.subTest(source=relative):
                added = self.root / relative
                added.write_text("// One additional source file.\n")
                _, scheme = generate()
                updated = objects()
                added_ids = set(updated) - set(original)
                self.assertEqual(len(added_ids), 4 if relative.startswith("CatLife/") else 2)  # Shared source builds in both apps.
                self.assertTrue(set(original).issubset(updated))

                def remove_added_references(value):
                    if isinstance(value, list):
                        return [remove_added_references(item) for item in value
                                if not isinstance(item, str) or item not in added_ids]
                    if isinstance(value, dict):
                        return {key: remove_added_references(item) for key, item in value.items()}
                    return value

                for identifier, value in original.items():
                    self.assertEqual(remove_added_references(updated[identifier]), value)
                self.assertEqual(scheme, baseline[1])
                added.unlink()
                self.assertEqual(generate(), baseline)

    def test_refresh_declares_concrete_media_metadata_and_directory_sandbox_inputs(self):
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["--root", str(self.root), "--update-manifest"]), 0)
        inputs = set((self.root / SANDBOX_INPUTS).read_text().splitlines())
        for path in [self.png, self.caf, self.png.parent / "Contents.json",
                     self.png.parent, self.png.parent.parent, self.caf.parent]:
            self.assertIn("$(SRCROOT)/" + path.relative_to(self.root).as_posix(), inputs)

    def failure_output(self):
        stderr = io.StringIO()
        with contextlib.redirect_stderr(stderr):
            self.assertEqual(main(["--root", str(self.root)]), 1)
        return stderr.getvalue()

    def test_missing_sandbox_list_points_to_restore_or_explicit_refresh(self):
        (self.root / SANDBOX_INPUTS).unlink()
        output = self.failure_output()
        self.assertIn(SANDBOX_INPUTS, output)
        self.assertIn("Restore", output)
        self.assertIn("--update-manifest", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)
        self.assertFalse((self.root / SANDBOX_INPUTS).exists())

    def test_stale_sandbox_list_is_not_a_media_download_error(self):
        path = self.root / SANDBOX_INPUTS
        path.write_text(path.read_text().replace("$(SRCROOT)/CatLife/Assets.xcassets/Contents.json\n", ""))
        before = path.read_bytes()
        output = self.failure_output()
        self.assertIn("stale sandbox input list", output)
        self.assertIn("--update-manifest", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)
        self.assertEqual(path.read_bytes(), before)

    def test_unreadable_sandbox_list_reports_access_and_inventory_recovery(self):
        read_text = Path.read_text

        def denied(path, *args, **kwargs):
            if path == self.root / SANDBOX_INPUTS:
                raise PermissionError("fixture denial")
            return read_text(path, *args, **kwargs)

        with patch.object(Path, "read_text", denied):
            output = self.failure_output()
        self.assertIn("PermissionError", output)
        self.assertIn("check file access permissions", output)
        self.assertIn("--update-manifest", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)

    def test_invalid_inventory_does_not_recommend_lfs_for_hydrated_media(self):
        (self.root / MANIFEST).write_text("broken JSON")
        output = self.failure_output()
        self.assertIn("invalid or missing runtime inventory", output)
        self.assertIn("--update-manifest", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)

    def test_explicit_refresh_updates_stale_lists_and_is_deterministic(self):
        added = self.caf.with_name("sfx-new.caf")
        added.write_bytes(self.caf.read_bytes())
        output = self.failure_output()
        self.assertIn("stale runtime inventory", output)
        self.assertIn("stale sandbox input list", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["--root", str(self.root), "--update-manifest"]), 0)
        before = [(self.root / name).read_bytes() for name in (MANIFEST, SANDBOX_INPUTS)]
        self.assertEqual(inspect(self.root)[1], [])
        with contextlib.redirect_stdout(io.StringIO()):
            self.assertEqual(main(["--root", str(self.root), "--update-manifest"]), 0)
        self.assertEqual([(self.root / name).read_bytes() for name in (MANIFEST, SANDBOX_INPUTS)], before)

    def test_generator_rejects_missing_or_stale_sandbox_list_before_replacing_project(self):
        scripts = Path(__file__).resolve().parent
        for filename in ("generate_project.rb", "check_runtime_assets.py"):
            (self.root / "scripts" / filename).write_bytes((scripts / filename).read_bytes())
        project = self.root / "CatLifeMac.xcodeproj/project.pbxproj"
        project.parent.mkdir()
        project.write_text("existing project must remain untouched\n")
        before = project.read_bytes()
        for state in ("missing", "stale"):
            with self.subTest(state=state):
                if state == "missing":
                    (self.root / SANDBOX_INPUTS).unlink()
                else:
                    (self.root / SANDBOX_INPUTS).write_text("$(SRCROOT)/CatLife/Audio\n")
                result = subprocess.run(["ruby", str(self.root / "scripts/generate_project.rb")],
                                        capture_output=True, text=True, check=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(SANDBOX_INPUTS, result.stderr)
                self.assertIn("--update-manifest", result.stderr)
                self.assertNotIn(DOWNLOAD_COMMAND, result.stderr)
                self.assertIn("the Xcode project was not changed", result.stderr)
                self.assertEqual(project.read_bytes(), before)

    def test_mixed_inventory_and_pointer_failures_keep_both_recovery_instructions(self):
        (self.root / SANDBOX_INPUTS).unlink()
        self.caf.write_bytes(LFS_HEADER)
        output = self.failure_output()
        self.assertIn(DOWNLOAD_COMMAND, output)
        self.assertIn("--update-manifest", output)

    def test_unreadable_media_reports_permissions_without_a_download_hint(self):
        open_file = Path.open

        def denied(path, *args, **kwargs):
            if path == self.caf:
                raise PermissionError("fixture denial")
            return open_file(path, *args, **kwargs)

        with patch.object(Path, "open", denied):
            output = self.failure_output()
        self.assertIn("unreadable runtime resource", output)
        self.assertIn("Xcode script sandbox inputs", output)
        self.assertNotIn(DOWNLOAD_COMMAND, output)


if __name__ == "__main__":
    unittest.main()
