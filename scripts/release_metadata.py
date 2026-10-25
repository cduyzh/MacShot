#!/usr/bin/env python3
"""校验唯一版本数据并生成仓库版本记录；打包时按实际构建信息写入应用。"""
import argparse
import datetime
import json
import pathlib
import plistlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
HISTORY_PATH = ROOT / "Sources/cduyzhShot/Resources/ReleaseHistory.json"


def release_history():
    history = json.loads(HISTORY_PATH.read_text())
    releases = history["releases"]
    if not releases:
        raise ValueError("版本记录不能为空")
    seen = set()
    previous_build = float("inf")
    for release in releases:
        if not re.fullmatch(r"\d+\.\d+\.\d+", release["version"]):
            raise ValueError("版本号应使用 major.minor.patch")
        if not re.fullmatch(r"[1-9]\d*", release["build"]):
            raise ValueError("构建号必须是正整数")
        identity = (release["version"], release["build"])
        if identity in seen or int(release["build"]) >= previous_build:
            raise ValueError("版本记录须按构建号倒序且不得重复")
        seen.add(identity)
        previous_build = int(release["build"])
        datetime.date.fromisoformat(release["date"])
        for key in ["title", "summary"]:
            if not release[key].strip():
                raise ValueError(f"缺少 {key}")
        if not release["highlights"] or not all(item.strip() for item in release["highlights"]):
            raise ValueError("更新内容不能为空")
    return history


def changelog(history):
    lines = ["# Version History", "", "This file is generated from the in-app ReleaseHistory.json; version, build number and content match the in-app records.", ""]
    for release in history["releases"]:
        lines += [f'## {release["version"]} (Build {release["build"]}) · {release["date"]}', "", release["title"], "", release["summary"], ""]
        lines += [f"- {item}" for item in release["highlights"]]
        if release.get("notes"):
            lines += ["", "Usage notes:", ""] + [f"- {item}" for item in release["notes"]]
        lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--write-changelog", action="store_true")
    parser.add_argument("--stamp-bundle", type=pathlib.Path)
    parser.add_argument("--revision")
    args = parser.parse_args()
    history = release_history()
    latest = history["releases"][0]
    with (ROOT / "Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (latest["version"], latest["build"]):
        raise ValueError("Info.plist 版本与首条更新记录不一致")
    log_path = ROOT / "CHANGELOG.md"
    if args.write_changelog:
        log_path.write_text(changelog(history))
    elif not log_path.exists() or log_path.read_text() != changelog(history):
        raise ValueError("CHANGELOG.md 与应用记录不一致；运行 --write-changelog 更新")
    if args.stamp_bundle:
        bundle = args.stamp_bundle
        info_path = bundle / "Contents/Info.plist"
        with info_path.open("rb") as file:
            bundled = plistlib.load(file)
        if (bundled["CFBundleShortVersionString"], bundled["CFBundleVersion"]) != (latest["version"], latest["build"]):
            raise ValueError("安装包版本与更新记录不一致")
        bundled["CDUYZHBuildDate"] = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        revision = args.revision
        if not revision:
            commit = subprocess.run(["git", "rev-parse", "--short=12", "HEAD"], cwd=ROOT, text=True, capture_output=True)
            revision = commit.stdout.strip() if commit.returncode == 0 else "unknown"
            dirty = subprocess.run(["git", "status", "--porcelain"], cwd=ROOT, text=True, capture_output=True)
            if dirty.stdout.strip():
                revision += "-modified"
        bundled["CDUYZHSourceRevision"] = revision
        bundled["CDUYZHReleaseDate"] = latest["date"]
        with info_path.open("wb") as file:
            plistlib.dump(bundled, file, sort_keys=False)
        target = bundle / "Contents/Resources/ReleaseHistory.json"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(HISTORY_PATH.read_text())
    print(f'版本记录一致：{latest["version"]}（构建 {latest["build"]}）')


if __name__ == "__main__":
    main()
