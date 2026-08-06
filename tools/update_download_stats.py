#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import json
import os
import re
import urllib.request
from pathlib import Path

REPOSITORY = os.environ.get(
    "GITHUB_REPOSITORY",
    "trigon1998/wordwise.koplugin-custom",
)
TOKEN = os.environ.get("GITHUB_TOKEN", "")
ROOT = Path(__file__).resolve().parents[1]
STATS_DIR = ROOT / "stats"
DATA_PATH = STATS_DIR / "downloads.json"
SVG_PATH = STATS_DIR / "downloads.svg"
BADGE_PATH = STATS_DIR / "downloads-badge.json"
ASSET_RE = re.compile(r"^wordwise\.koplugin-v.+\.zip$")


def fetch_releases() -> list[dict]:
    releases: list[dict] = []
    page = 1
    while True:
        url = (
            f"https://api.github.com/repos/{REPOSITORY}/releases"
            f"?per_page=100&page={page}"
        )
        headers = {
            "Accept": "application/vnd.github+json",
            "User-Agent": "wordwise-download-stats",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        if TOKEN:
            headers["Authorization"] = f"Bearer {TOKEN}"
        request = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(request, timeout=30) as response:
            batch = json.loads(response.read().decode("utf-8"))
        if not batch:
            break
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    return releases


def plugin_downloads(releases: list[dict]) -> tuple[int, list[dict]]:
    total = 0
    assets: list[dict] = []
    for release in releases:
        if release.get("draft"):
            continue
        for asset in release.get("assets", []):
            name = str(asset.get("name", ""))
            if not ASSET_RE.fullmatch(name):
                continue
            count = int(asset.get("download_count", 0))
            total += count
            assets.append(
                {
                    "release": release.get("tag_name"),
                    "asset": name,
                    "downloads": count,
                }
            )
    assets.sort(key=lambda item: (str(item["release"]), str(item["asset"])))
    return total, assets


def load_data() -> dict:
    if DATA_PATH.exists():
        return json.loads(DATA_PATH.read_text(encoding="utf-8"))
    return {
        "repository": REPOSITORY,
        "metric": "plugin_zip_downloads",
        "asset_pattern": ASSET_RE.pattern,
        "snapshots": [],
        "assets": [],
    }


def save_svg(snapshots: list[dict], total: int) -> None:
    width, height = 920, 300
    left, right, top, bottom = 70, 25, 52, 58
    plot_w = width - left - right
    plot_h = height - top - bottom
    points = snapshots[-120:] or [{"date": dt.date.today().isoformat(), "downloads": total}]
    values = [int(point["downloads"]) for point in points]
    minimum = min(values)
    maximum = max(values)
    if maximum == minimum:
        minimum = max(0, minimum - 1)
        maximum += 1

    def x_at(index: int) -> float:
        if len(points) == 1:
            return left + plot_w / 2
        return left + plot_w * index / (len(points) - 1)

    def y_at(value: int) -> float:
        return top + plot_h * (maximum - value) / (maximum - minimum)

    polyline = " ".join(
        f"{x_at(index):.1f},{y_at(value):.1f}"
        for index, value in enumerate(values)
    )
    first_date = points[0]["date"]
    last_date = points[-1]["date"]
    increase = values[-1] - values[0]

    grid = []
    labels = []
    for step in range(5):
        value = minimum + (maximum - minimum) * step / 4
        y = y_at(round(value))
        grid.append(
            f'<line x1="{left}" y1="{y:.1f}" x2="{width-right}" y2="{y:.1f}" '
            'stroke="#d7dce2" stroke-width="1"/>'
        )
        labels.append(
            f'<text x="{left-10}" y="{y+5:.1f}" text-anchor="end" '
            'font-family="system-ui, sans-serif" font-size="12" fill="#667085">'
            f'{round(value):,}</text>'
        )

    dots = ""
    if len(points) == 1:
        dots = (
            f'<circle cx="{x_at(0):.1f}" cy="{y_at(values[0]):.1f}" '
            'r="5" fill="#2563eb"/>'
        )

    svg = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}" role="img" aria-labelledby="title desc">
  <title id="title">Word Wise plugin ZIP download history</title>
  <desc id="desc">Cumulative downloads of plugin ZIP release assets, excluding checksums and database packages.</desc>
  <rect width="{width}" height="{height}" rx="16" fill="#ffffff" stroke="#d0d5dd"/>
  <text x="{left}" y="30" font-family="system-ui, sans-serif" font-size="18" font-weight="700" fill="#101828">Plugin ZIP downloads</text>
  <text x="{width-right}" y="30" text-anchor="end" font-family="system-ui, sans-serif" font-size="18" font-weight="700" fill="#2563eb">{total:,}</text>
  {''.join(grid)}
  {''.join(labels)}
  <line x1="{left}" y1="{top+plot_h}" x2="{width-right}" y2="{top+plot_h}" stroke="#98a2b3"/>
  <polyline points="{polyline}" fill="none" stroke="#2563eb" stroke-width="3" stroke-linejoin="round" stroke-linecap="round"/>
  {dots}
  <text x="{left}" y="{height-30}" font-family="system-ui, sans-serif" font-size="12" fill="#667085">{first_date}</text>
  <text x="{width-right}" y="{height-30}" text-anchor="end" font-family="system-ui, sans-serif" font-size="12" fill="#667085">{last_date}</text>
  <text x="{width/2}" y="{height-30}" text-anchor="middle" font-family="system-ui, sans-serif" font-size="12" fill="#667085">Change in displayed period: +{increase:,}</text>
  <text x="{width/2}" y="{height-10}" text-anchor="middle" font-family="system-ui, sans-serif" font-size="11" fill="#98a2b3">Counts only wordwise.koplugin-v*.zip release assets</text>
</svg>
'''
    SVG_PATH.write_text(svg, encoding="utf-8")


def main() -> None:
    STATS_DIR.mkdir(parents=True, exist_ok=True)
    releases = fetch_releases()
    total, assets = plugin_downloads(releases)
    data = load_data()
    today = dt.datetime.now(dt.timezone.utc).date().isoformat()
    snapshots = list(data.get("snapshots", []))
    current = {"date": today, "downloads": total}
    if snapshots and snapshots[-1].get("date") == today:
        snapshots[-1] = current
    else:
        snapshots.append(current)

    data.update(
        {
            "repository": REPOSITORY,
            "metric": "plugin_zip_downloads",
            "asset_pattern": ASSET_RE.pattern,
            "updated_at": dt.datetime.now(dt.timezone.utc).isoformat(),
            "snapshots": snapshots,
            "assets": assets,
        }
    )
    DATA_PATH.write_text(
        json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    BADGE_PATH.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "label": "plugin downloads",
                "message": f"{total:,}",
                "color": "2563eb",
            },
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )
    save_svg(snapshots, total)
    print(f"Tracked plugin ZIP downloads: {total}")


if __name__ == "__main__":
    main()
