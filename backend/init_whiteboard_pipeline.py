#!/usr/bin/env python
"""Initialize whiteboard pipeline folders and run one pipeline call."""

from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


def configure_utf8_stdio() -> None:
    os.environ.setdefault("PYTHONUTF8", "1")
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    for stream_name in ("stdout", "stderr"):
        stream = getattr(sys, stream_name, None)
        if stream is not None and hasattr(stream, "reconfigure"):
            try:
                stream.reconfigure(encoding="utf-8", errors="replace")
            except Exception:
                pass


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Initialize whiteboard pipeline runtime folders and run one pipeline request."
    )
    parser.add_argument("--query", default="Eukaryotic cell", help="Prompt query text.")
    parser.add_argument("--subject", default="Biology", help="Prompt subject/topic.")
    parser.add_argument(
        "--model-id",
        default="Qwen/Qwen3-VL-2B-Instruct",
        help="Vision-language model ID used by the pipeline.",
    )
    parser.add_argument("--gpu-index", type=int, default=0, help="CUDA GPU index.")
    parser.add_argument(
        "--top-n-per-prompt",
        type=int,
        default=1,
        help="Number of processed IDs to return per prompt.",
    )
    parser.add_argument(
        "--min-final-score",
        type=float,
        default=0.78,
        help="Minimum fusion score for Pinecone fetch acceptance.",
    )
    parser.add_argument(
        "--min-modalities",
        type=int,
        default=3,
        help="Minimum modalities required in rank fusion.",
    )
    parser.add_argument(
        "--top-k-per-modality",
        type=int,
        default=50,
        help="Top-K candidates per modality before fusion.",
    )
    parser.add_argument(
        "--dirs-only",
        action="store_true",
        help="Only create folders; do not execute the pipeline call.",
    )
    return parser.parse_args()


def ensure_runtime_dirs(backend_dir: Path) -> list[Path]:
    wb_dir = backend_dir / "whiteboard_backend"
    dirs = [
        wb_dir / "ResearchImages",
        wb_dir / "ResearchImages" / "UniqueImages",
        wb_dir / "PipelineOutputs",
        wb_dir / "terminal_buckets",
        wb_dir / "source_urls",
        wb_dir / "_path_cache",
    ]
    for path in dirs:
        path.mkdir(parents=True, exist_ok=True)
    return dirs


def run_pipeline_once(args: argparse.Namespace) -> int:
    configure_utf8_stdio()

    backend_dir = Path(__file__).resolve().parent
    os.chdir(backend_dir)

    created_dirs = ensure_runtime_dirs(backend_dir)
    print("[init] ensured runtime folders:")
    for path in created_dirs:
        print(f"  - {path}")

    if args.dirs_only:
        print("[init] --dirs-only set; skipping pipeline execution.")
        return 0

    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "backend.settings")
    import django

    django.setup()

    from django.test import Client

    payload = {
        "query": args.query,
        "subject": args.subject,
        "model_id": args.model_id,
        "gpu_index": args.gpu_index,
        "top_n_per_prompt": args.top_n_per_prompt,
        "min_final_score": args.min_final_score,
        "min_modalities": args.min_modalities,
        "top_k_per_modality": args.top_k_per_modality,
    }

    print("[init] calling POST /api/wb/pipeline/image-pipeline/ ...")
    print("[init] payload:", json.dumps(payload, ensure_ascii=False))

    client = Client()
    response = client.post(
        "/api/wb/pipeline/image-pipeline/",
        data=json.dumps(payload, ensure_ascii=False),
        content_type="application/json",
    )

    print(f"[init] status: {response.status_code}")
    body_text = response.content.decode("utf-8", errors="replace")
    try:
        body_json = json.loads(body_text)
    except json.JSONDecodeError:
        body_json = None

    if body_json is not None:
        print("[init] response:", json.dumps(body_json, indent=2, ensure_ascii=False))
    else:
        print("[init] response (raw):", body_text)

    if response.status_code != 200:
        return 1

    if isinstance(body_json, dict) and not body_json.get("ok", False):
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(run_pipeline_once(parse_args()))
