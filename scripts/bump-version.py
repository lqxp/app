#!/usr/bin/env python3
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PACKAGE_JSON = ROOT / "package.json"
CLIENT_DIR = ROOT / "client"
CLIENT_PACKAGE_JSON = CLIENT_DIR / "package.json"
CARGO_TOML = ROOT / "src-tauri" / "Cargo.toml"
TAURI_CONF = ROOT / "src-tauri" / "tauri.conf.json"
QXCHAT_NIX = ROOT / "nix" / "qxchat.nix"
SEMVER_RE = re.compile(r"^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


class Color:
    RED = "\033[31m"
    GREEN = "\033[32m"
    BLUE = "\033[34m"
    YELLOW = "\033[33m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def paint(text: str, color: str) -> str:
    return f"{color}{text}{Color.RESET}"


def die(message: str) -> None:
    print(paint(f"Error: {message}", Color.RED), file=sys.stderr)
    sys.exit(1)


def run_git(args: list[str], cwd: Path = ROOT, capture: bool = False) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=cwd,
            check=True,
            text=True,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE if capture else None,
        )
    except FileNotFoundError:
        die("git is required")
    except subprocess.CalledProcessError as exc:
        if capture and exc.stderr:
            die(exc.stderr.strip())
        die(f"git {' '.join(args)} failed")

    return result.stdout.strip() if capture else ""


def is_git_repo(path: Path) -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--is-inside-work-tree"],
            cwd=path,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except (FileNotFoundError, subprocess.CalledProcessError):
        return False


def has_changes(cwd: Path, paths: list[str]) -> bool:
    return bool(run_git(["status", "--short", "--", *paths], cwd=cwd, capture=True))


def commit_changes(cwd: Path, paths: list[str], message: str) -> bool:
    if not has_changes(cwd, paths):
        return False
    run_git(["add", "--", *paths], cwd=cwd)
    run_git(["commit", "-m", message], cwd=cwd)
    return True


def tag_exists(cwd: Path, tag_name: str) -> bool:
    try:
        subprocess.run(
            ["git", "rev-parse", "--verify", f"refs/tags/{tag_name}"],
            cwd=cwd,
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return True
    except subprocess.CalledProcessError:
        return False


def create_version_tag(cwd: Path, version: str, push: bool) -> None:
    tag_name = f"v{version}"
    if tag_exists(cwd, tag_name):
        die(f"Tag {tag_name} already exists in {cwd}")

    run_git(["tag", tag_name], cwd=cwd)

    if push:
        run_git(["push", "origin", "HEAD"], cwd=cwd)
        run_git(["push", "origin", tag_name], cwd=cwd)


def parse_semver(version: str) -> tuple[int, int, int]:
    match = SEMVER_RE.match(version)
    if not match:
        die(f"Invalid version '{version}'. Expected format: MAJOR.MINOR.PATCH (e.g. 1.2.3)")
    return int(match.group(1)), int(match.group(2)), int(match.group(3))


def bump_version(current: str, kind: str) -> str:
    major, minor, patch = parse_semver(current)
    if kind == "major":
        return f"{major + 1}.0.0"
    if kind == "minor":
        return f"{major}.{minor + 1}.0"
    if kind == "patch":
        return f"{major}.{minor}.{patch + 1}"
    die(f"Unknown bump type: {kind}")


def load_package_version() -> str:
    try:
        data = json.loads(PACKAGE_JSON.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"File not found: {PACKAGE_JSON}")
    except json.JSONDecodeError as exc:
        die(f"Invalid JSON in {PACKAGE_JSON}: {exc}")

    version = data.get("version")
    if not isinstance(version, str):
        die("Missing or invalid 'version' field in package.json")

    parse_semver(version)
    return version


def write_json_version(path: Path, version: str) -> None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        die(f"File not found: {path}")
    except json.JSONDecodeError as exc:
        die(f"Invalid JSON in {path}: {exc}")

    data["version"] = version
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def write_package_version(version: str) -> None:
    write_json_version(PACKAGE_JSON, version)


def write_client_package_version(version: str) -> None:
    if not CLIENT_PACKAGE_JSON.exists():
        print(paint(f"Warning: {CLIENT_PACKAGE_JSON} not found, skipping", Color.YELLOW))
        return
    write_json_version(CLIENT_PACKAGE_JSON, version)


def write_tauri_conf_version(version: str) -> None:
    write_json_version(TAURI_CONF, version)


def write_cargo_version(version: str) -> None:
    try:
        content = CARGO_TOML.read_text(encoding="utf-8")
    except FileNotFoundError:
        die(f"File not found: {CARGO_TOML}")

    package_section_match = re.search(r"(?ms)^\[package\]\n(.*?)(?=^\[|\Z)", content)
    if not package_section_match:
        die("[package] section not found in src-tauri/Cargo.toml")

    package_section = package_section_match.group(1)
    if not re.search(r"(?m)^version\s*=\s*\"[^\"]+\"\s*$", package_section):
        die("version key not found in Cargo.toml [package] section")

    updated_package_section = re.sub(
        r"(?m)^version\s*=\s*\"[^\"]+\"\s*$",
        f'version = "{version}"',
        package_section,
        count=1,
    )

    start, end = package_section_match.span(1)
    updated_content = content[:start] + updated_package_section + content[end:]
    CARGO_TOML.write_text(updated_content, encoding="utf-8")


def write_qxchat_nix_version(version: str) -> None:
    try:
        content = QXCHAT_NIX.read_text(encoding="utf-8")
    except FileNotFoundError:
        die(f"File not found: {QXCHAT_NIX}")

    if not re.search(r'(?m)^\s*version\s*=\s*"[^"]+"\s*;', content):
        die("version key not found in nix/qxchat.nix")

    updated_content = re.sub(
        r'(?m)^(\s*)version\s*=\s*"[^"]+"\s*;',
        rf'\1version = "{version}";',
        content,
        count=1,
    )
    QXCHAT_NIX.write_text(updated_content, encoding="utf-8")


def release_version(version: str, push: bool) -> None:
    tag_name = f"v{version}"
    if tag_exists(ROOT, tag_name):
        die(f"Tag {tag_name} already exists in {ROOT}")

    client_is_git_repo = CLIENT_PACKAGE_JSON.exists() and is_git_repo(CLIENT_DIR)
    if client_is_git_repo and tag_exists(CLIENT_DIR, tag_name):
        die(f"Tag {tag_name} already exists in {CLIENT_DIR}")
    if CLIENT_PACKAGE_JSON.exists() and not client_is_git_repo:
        print(paint("Warning: client is not a git repository, web tag skipped", Color.YELLOW))

    if client_is_git_repo:
        commit_changes(CLIENT_DIR, ["package.json"], f"Release v{version}")
        create_version_tag(CLIENT_DIR, version, push)
        print(paint(f"Web client tagged as v{version}", Color.GREEN))

    commit_changes(
        ROOT,
        ["package.json", "src-tauri/Cargo.toml", "src-tauri/tauri.conf.json", "nix/qxchat.nix", "client"],
        f"Release v{version}",
    )
    create_version_tag(ROOT, version, push)


def usage() -> None:
    print(paint("Usage:", Color.BOLD))
    print(paint("  python3 scripts/bump-version.py patch|minor|major [--no-push]", Color.BLUE))
    print(paint("  python3 scripts/bump-version.py set <version>", Color.BLUE))


def main() -> None:
    if len(sys.argv) < 2:
        usage()
        sys.exit(1)

    cmd = sys.argv[1]
    push = "--no-push" not in sys.argv[2:]

    if cmd in {"patch", "minor", "major"}:
        current_version = load_package_version()
        new_version = bump_version(current_version, cmd)
        should_release = True
    elif cmd == "set":
        if len(sys.argv) != 3:
            usage()
            sys.exit(1)
        new_version = sys.argv[2]
        parse_semver(new_version)
        should_release = False
    else:
        usage()
        sys.exit(1)

    write_package_version(new_version)
    write_client_package_version(new_version)
    write_cargo_version(new_version)
    write_tauri_conf_version(new_version)
    write_qxchat_nix_version(new_version)

    if should_release:
        release_version(new_version, push)

    print(paint(f"Version updated to {new_version}", Color.GREEN))
    print(paint("Updated files:", Color.BOLD))
    print(paint("  - package.json", Color.YELLOW))
    if CLIENT_PACKAGE_JSON.exists():
        print(paint("  - client/package.json", Color.YELLOW))
    print(paint("  - src-tauri/Cargo.toml", Color.YELLOW))
    print(paint("  - src-tauri/tauri.conf.json", Color.YELLOW))
    print(paint("  - nix/qxchat.nix", Color.YELLOW))
    if should_release:
        print(paint(f"Created tag v{new_version} in app and web client", Color.YELLOW))
        if push:
            print(paint("Pushed commits and tags to GitHub", Color.YELLOW))


if __name__ == "__main__":
    main()
