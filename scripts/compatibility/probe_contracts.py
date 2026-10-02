#!/usr/bin/env python3
"""Generate isolated MoviePilot subscription-contract fixtures from trusted local Git tags.

This executes upstream schema/router source, not a MoviePilot service. No login,
external HTTP call, database or real subscription mutation is performed. A local
FastAPI TestClient calls a harmless stub to exercise response serialization.

Tested dependency versions are in requirements.txt. The generated manifest
records the actual Python/dependency versions; these need not match upstream's
runtime lockfile and must not be described as live-backend verification.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.metadata
import json
import pathlib
import platform
import re
import subprocess
import sys
import types
from typing import Any

from fastapi import FastAPI
from fastapi.testclient import TestClient

SCHEMA_FILES = (
    "app/schemas/types.py",
    "app/schemas/media.py",
    "app/schemas/common.py",
    "app/schemas/response.py",
    "app/schemas/subscribe.py",
    "app/schemas/category.py",
    "app/schemas/music.py",
    "app/schemas/context.py",
    "app/api/response.py",
)
DEPENDENCIES = ("fastapi", "pydantic", "httpx", "typing_extensions", "starlette")


def git(repo: pathlib.Path, *args: str) -> str:
    return subprocess.check_output(["git", "-C", str(repo), *args], text=True)


def read_source(repo: pathlib.Path, commit: str, path: str) -> str:
    return git(repo, "show", f"{commit}:{path}")


def load_module(name: str, source: str) -> types.ModuleType:
    module = types.ModuleType(name)
    sys.modules[name] = module
    exec(compile(source, name, "exec"), module.__dict__)
    return module


def install_isolated_packages() -> None:
    """Avoid importing MoviePilot's runtime/application initialization."""
    for name in tuple(sys.modules):
        if name == "app" or name.startswith("app."):
            del sys.modules[name]
    for name in ("app", "app.schemas", "app.runtime", "app.api"):
        module = types.ModuleType(name)
        module.__path__ = []
        sys.modules[name] = module
    # Only localization/error-message dependencies are replaced. The public
    # schema validators and the ResponseAPIRoute implementation stay unchanged.
    load_module(
        "app.runtime.localization",
        "class LocaleHelper:\n"
        " @staticmethod\n"
        " def translate_text(value, locale=None): return value\n"
        " @staticmethod\n"
        " def get_current_locale(): return 'zh-CN'\n",
    )
    load_module("app.runtime.errors", "def public_error_message(value): return value\n")


def dump_json(path: pathlib.Path, value: Any) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def probe(repo: pathlib.Path, tag: str, output: pathlib.Path) -> dict[str, Any]:
    if not re.fullmatch(r"v?\d+\.\d+\.\d+(?:-[A-Za-z0-9.]+)?", tag):
        raise ValueError(f"Unsupported fixture tag syntax: {tag}")
    commit = git(repo, "rev-parse", "--verify", f"{tag}^{{commit}}").strip()
    install_isolated_packages()
    sources = {path: read_source(repo, commit, path) for path in SCHEMA_FILES}
    modules = {
        path: load_module(path[:-3].replace("/", "."), contents)
        for path, contents in sources.items()
    }
    subscribe = modules["app/schemas/subscribe.py"].Subscribe
    response = modules["app/schemas/response.py"].Response
    id_data = modules["app/schemas/common.py"].IdData
    endpoint_source = read_source(repo, commit, "app/api/endpoints/subscribe.py")
    version_source = read_source(repo, commit, "version.py")
    frontend_match = re.search(r"FRONTEND_VERSION\s*=\s*['\"]([^'\"]+)", version_source)
    fork_annotation = re.search(
        r'@router\.post\("/fork",\s*summary="复用订阅",\s*response_model=_SchemaResponse\[([^\]]+)\]',
        endpoint_source,
    )
    if not fork_annotation or fork_annotation.group(1) not in ("None", "_SchemaIdData"):
        raise ValueError(f"{tag}: Fork response declaration changed; review source before extending probe")
    fork_has_id = fork_annotation.group(1) == "_SchemaIdData"

    detail_input = {
        "id": 42, "name": "契约样本", "type": "电视剧", "year": "2026",
        "media_source": "themoviedb", "media_id": "100", "season": 1,
        "total_episode": 12, "start_episode": 1, "lack_episode": 7, "best_version": 0,
        "sites": [1, 2], "filter_groups": ["保留规则"], "search_interval": 24,
        "media_category_id": "stable-category", "media_category": "电视剧/契约",
        "episode_group": "group-1", "audio_quality": "lossless", "audio_format": "FLAC",
        "min_bitrate": 320000, "min_bit_depth": 24, "min_sample_rate": 96000,
        "username": "fixture-owner", "state": "R", "current_priority": 50, "note": [1, 2],
    }
    detail_response = response[subscribe](
        success=True, data=subscribe.model_validate(detail_input)
    ).model_dump(mode="json")
    update_request = {
        "id": 42, "include": "", "exclude": "", "quality": "", "sites": [],
        "filter_groups": [], "search_interval": None, "episode_group": None,
        "media_category_id": None, "media_source": None, "media_id": None,
        "username": "must-not-write", "state": "S", "completed_episode": 9,
    }
    writable_projection = subscribe.model_validate(update_request).to_public_write_payload(exclude_unset=True)
    media_info = modules["app/schemas/context.py"].MediaInfo
    media_response = response[media_info](success=True, data=media_info.model_validate({
        "media_source": "themoviedb", "media_id": "100", "type": "电视剧",
        "title": "契约样本", "year": "2026", "season": 1,
        "seasons": {"1": [1, 2]}, "season_years": {"1": "2026"},
        "episode_group": "group-1",
        "season_info": [{"season_number": 1, "episode_count": 2, "name": "Season 1"}],
        "actors": [{"id": 10, "name": "演员样本", "images": {"large": "https://example.invalid/person.jpg"}}],
        "directors": ["导演样本"],
    })).model_dump(mode="json")
    counter = {"created": 0}

    async def harmless_fork_stub() -> Any:
        counter["created"] += 1
        return response(success=True, data={"id": 42})

    router = modules["app/api/response.py"].ResponseAPIRouter()
    router.add_api_route(
        "/subscribe/fork", harmless_fork_stub, methods=["POST"],
        response_model=response[id_data if fork_has_id else None],
    )
    app = FastAPI()
    app.include_router(router)
    with TestClient(app, raise_server_exceptions=False) as client:
        actual = client.post("/subscribe/fork")
    expected_status = 200 if fork_has_id else 500
    if actual.status_code != expected_status or counter["created"] != 1:
        raise AssertionError(f"{tag}: fork serialization changed: {actual.status_code}, {counter}")
    if fork_has_id and actual.json().get("data", {}).get("id") != 42:
        raise AssertionError(f"{tag}: successful fork did not retain its created ID")
    forbidden = set(subscribe.PUBLIC_WRITE_EXCLUDED_FIELDS)
    if forbidden.intersection(writable_projection):
        raise AssertionError(f"{tag}: public write projection exposed excluded fields")
    for field in ("include", "exclude", "quality", "search_interval", "episode_group", "media_category_id"):
        if field not in writable_projection or writable_projection[field] is not None:
            raise AssertionError(f"{tag}: explicit clear semantics changed for {field}")
    for field in ("sites", "filter_groups"):
        if writable_projection.get(field) != []:
            raise AssertionError(f"{tag}: empty selection semantics changed for {field}")
    provenance = {
        "kind": "upstream-schema-generated; isolated stub endpoint",
        "backend_tag": tag, "backend_commit": commit,
        "frontend_tag": frontend_match.group(1) if frontend_match else None,
        "not_live_backend": True, "localization_stubbed": True,
        "python": platform.python_version(),
        "dependencies": {name: importlib.metadata.version(name) for name in DEPENDENCIES},
        "source_sha256": {path: hashlib.sha256(text.encode()).hexdigest() for path, text in sources.items()},
        "source_urls": {
            path: f"https://github.com/jxxghp/MoviePilot/blob/{commit}/{path}"
            for path in (*SCHEMA_FILES, "app/api/endpoints/subscribe.py", "version.py")
        },
    }
    fixture = {
        "provenance": provenance,
        "checks": {"fork_serialization": "passed", "write_projection_and_clears": "passed"},
        "subscription_detail_response": detail_response,
        "media_detail_response": media_response,
        "subscription_update_request": update_request,
        "subscription_update_writable_projection": writable_projection,
        "subscription_public_write_excluded_fields": sorted(subscribe.PUBLIC_WRITE_EXCLUDED_FIELDS),
        "fork": {
            "declared_data": "IdData" if fork_has_id else "None",
            "status": actual.status_code,
            "body": actual.json() if actual.headers.get("content-type", "").startswith("application/json") else actual.text,
            "stub_creation_count": counter["created"],
            "note": "The generic 500 body is from this isolated FastAPI app, not MoviePilot's global error handler.",
        },
    }
    dump_json(output / f"{tag}.json", fixture)
    return {
        "tag": tag, "backend_commit": commit, "frontend_tag": provenance["frontend_tag"],
        "fixture": f"{tag}.json", "source_sha256": provenance["source_sha256"],
        "fork_status": actual.status_code, "subscription_field_count": len(subscribe.model_fields),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--backend-repo", required=True, type=pathlib.Path, help="Trusted local jxxghp/MoviePilot Git checkout")
    parser.add_argument("--output", required=True, type=pathlib.Path, help="Generated fixture directory")
    parser.add_argument("--tags", required=True, nargs="+", help="Locally available release tags to probe")
    args = parser.parse_args()
    git(args.backend_repo, "rev-parse", "--git-dir")
    args.output.mkdir(parents=True, exist_ok=True)
    results = [probe(args.backend_repo, tag, args.output) for tag in args.tags]
    dump_json(args.output / "manifest.json", {
        "scope": "Isolated schema/response-serialization checks. No live backend, DB, login or mutation verification.",
        "python": platform.python_version(),
        "dependencies": {name: importlib.metadata.version(name) for name in DEPENDENCIES},
        "results": results,
    })
    print(json.dumps(results, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
