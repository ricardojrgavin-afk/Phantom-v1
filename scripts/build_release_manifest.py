from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

VERSION_FILE = ROOT / "version.json"
MANIFEST_FILE = ROOT / "release-manifest.json"
RUNTIME_ROOT_FILES = [
    "Main.lua",
    "loader.lua",
    "GuiLibrary.lua",
    "version.json",
]

RUNTIME_DIRECTORIES = [
    "src",
    "games",
    "lib",
]


def sha256_for(path: Path) -> str:
    digest = hashlib.sha256()
    digest.update(path.read_bytes())
    return digest.hexdigest()


def iter_runtime_files() -> list[Path]:
    files: list[Path] = []

    for relative_path in RUNTIME_ROOT_FILES:
        path = ROOT / relative_path
        if path.is_file():
            files.append(path)

    for directory in RUNTIME_DIRECTORIES:
        base = ROOT / directory
        if not base.exists():
            continue

        for path in sorted(base.rglob("*")):
            if path.is_file():
                files.append(path)

    return sorted(files)


def read_version() -> dict:
    data = json.loads(VERSION_FILE.read_text(encoding="utf-8"))
    return {
        "name": data.get("name", "Phantom"),
        "channel": data.get("channel", "stable"),
        "major": int(data.get("major", 0)),
        "minor": int(data.get("minor", 0)),
        "patch": int(data.get("patch", 0)),
    }


def write_github_output(version: str, tag: str) -> None:
    output_path = os.environ.get("GITHUB_OUTPUT")
    if not output_path:
        return

    with open(output_path, "a", encoding="utf-8") as handle:
        handle.write(f"version={version}\n")
        handle.write(f"tag={tag}\n")


def main() -> None:
    version_info = read_version()

    run_number = os.environ.get("GITHUB_RUN_NUMBER", "0")
    repository = os.environ.get("GITHUB_REPOSITORY", "XzynAstralz/Phantom")

    repo_owner, repo_name = repository.split("/", 1)

    base_version = f"{version_info['major']}.{version_info['minor']}.{version_info['patch']}"
    full_version = f"{base_version}+{run_number}"
    tag = f"v{base_version}-build{run_number}"

    files = []
    for path in iter_runtime_files():
        relative_path = path.relative_to(ROOT).as_posix()
        files.append({
            "path": relative_path,
            "sha256": sha256_for(path),
            "size": path.stat().st_size,
        })

    manifest = {
        "name": version_info["name"],
        "channel": version_info["channel"],
        "version": full_version,
        "baseVersion": base_version,
        "releaseTag": tag,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "rawBaseUrl": f"https://raw.githubusercontent.com/{repo_owner}/{repo_name}/{tag}/",
        "preserve": ["storage"],
        "files": files,
    }

    MANIFEST_FILE.write_text(
        json.dumps(manifest, indent=2),
        encoding="utf-8"
    )

    write_github_output(full_version, tag)


if __name__ == "__main__":
    main()
