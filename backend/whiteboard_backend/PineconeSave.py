# ImagePineconeSave.py
from __future__ import annotations

import os
import time as _time
from typing import Any, Dict, List, Optional

from pinecone.grpc import PineconeGRPC as Pinecone  # per docs

from dotenv import load_dotenv
from pathlib import Path

load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")


def _log(msg: str) -> None:
    ts = _time.strftime("%H:%M:%S")
    print(f"[{ts}][PineconeSave] {msg}", flush=True)


# -----------------------------
# SETTINGS (env-driven)
# -----------------------------
PINECONE_API_KEY = os.getenv("PINECONE_API_KEY") or os.getenv("Pinecone-API-Key", "")
PINECONE_INDEX_NAME = os.getenv("PINECONE_INDEX_NAME", "lesson-images")

UPSERT_BATCH = int(os.getenv("PINECONE_UPSERT_BATCH", "100"))


def _chunked(lst: List[Any], n: int) -> List[List[Any]]:
    return [lst[i:i+n] for i in range(0, len(lst), n)]


def _vec_dim(v: Any) -> Optional[int]:
    if isinstance(v, list) and v and all(isinstance(x, (int, float)) for x in v):
        return len(v)
    return None


def _index_exists(pc: Pinecone, index_name: str) -> bool:
    try:
        pc.describe_index(index_name)
        return True
    except Exception:
        return False


def _open_index(pc: Pinecone, index_name: str):
    desc = pc.describe_index(index_name)
    host = getattr(desc, "host", None)
    if not host:
        # Some SDK variants return dict-like
        host = desc.get("host") if isinstance(desc, dict) else None
    if not host:
        raise RuntimeError(f"Could not resolve host for index: {index_name}")
    return pc.Index(host=host)


def _index_dimension(pc: Pinecone, index_name: str) -> int:
    desc = pc.describe_index(index_name)
    dim = getattr(desc, "dimension", None)
    if dim is None and isinstance(desc, dict):
        dim = desc.get("dimension")
    if dim is None:
        spec = getattr(desc, "spec", None)
        if spec is not None:
            dim = getattr(spec, "dimension", None)
        if dim is None and isinstance(spec, dict):
            dim = spec.get("dimension")
    if dim is None:
        raise RuntimeError(f"Could not resolve dimension for index: {index_name}")
    return int(dim)


def upsert_image_metadata_embeddings(jobs: List[Dict[str, Any]]) -> Dict[str, Any]:
    """
    jobs item format expected (built in ImagePipeline.py):
      {
        "processed_id": "processed_0",
        "unique_path": "...",
        "prompt_embedding": [...],
        "clip_embedding": [...],
        "context_embedding": [...],  # best ctx_embedding
        "meta": {... small metadata ...}
      }

    Returns a summary dict (counts + index plan).
    """
    _log(f"upsert called with {len(jobs)} job(s)")

    if not PINECONE_API_KEY:
        _log("ERROR: PINECONE_API_KEY is missing")
        raise RuntimeError("PINECONE_API_KEY is missing in environment variables.")

    # Infer dims from first available vector of each type
    prompt_dim = None
    clip_dim = None
    context_dim = None

    for j in jobs:
        if prompt_dim is None:
            prompt_dim = _vec_dim(j.get("prompt_embedding"))
        if clip_dim is None:
            clip_dim = _vec_dim(j.get("clip_embedding"))
        if context_dim is None:
            context_dim = _vec_dim(j.get("context_embedding"))
        if prompt_dim and clip_dim and context_dim:
            break

    _log(f"Inferred dims: prompt={prompt_dim}, clip={clip_dim}, context={context_dim}")

    pc = Pinecone(api_key=PINECONE_API_KEY)

    if not _index_exists(pc, PINECONE_INDEX_NAME):
        _log(f"ERROR: Index ‘{PINECONE_INDEX_NAME}’ not found")
        raise RuntimeError(
            f"Pinecone index not found: ‘{PINECONE_INDEX_NAME}’. "
            "Set PINECONE_INDEX_NAME to an existing index."
        )

    index_dim = _index_dimension(pc, PINECONE_INDEX_NAME)
    _log(f"Index ‘{PINECONE_INDEX_NAME}’ dimension: {index_dim}")
    dims = {"prompt": prompt_dim, "clip": clip_dim, "context": context_dim}
    plan: Dict[str, tuple[str, str]] = {}
    skipped_modalities: Dict[str, str] = {}
    for kind, dim in dims.items():
        if dim is None:
            skipped_modalities[kind] = "missing_vector"
            continue
        if int(dim) != int(index_dim):
            skipped_modalities[kind] = f"dim_mismatch(vector={dim}, index={index_dim})"
            continue
        plan[kind] = (PINECONE_INDEX_NAME, kind)

    if skipped_modalities:
        _log(f"Skipped modalities: {skipped_modalities}")
    _log(f"Upsert plan: {list(plan.keys())}")

    if not plan:
        _log(f"ERROR: No embeddings match index dimension {index_dim}")
        raise RuntimeError(
            f"No embeddings match Pinecone index dimension {index_dim} "
            f"for index ‘{PINECONE_INDEX_NAME}’."
        )

    index = _open_index(pc, PINECONE_INDEX_NAME)

    counts = {"prompt": 0, "clip": 0, "context": 0}

    # Build per-kind upsert payloads for compatible modalities only.
    per_kind_vectors: Dict[str, List[Dict[str, Any]]] = {k: [] for k in plan.keys()}

    for j in jobs:
        pid = str(j.get("processed_id", "")).strip()
        upath = str(j.get("unique_path", "")).strip()
        meta = j.get("meta") if isinstance(j.get("meta"), dict) else {}

        # Keep metadata small; don’t shove full texts/arrays into Pinecone metadata.
        base_ctx = str(j.get("base_context", "") or "").strip()

        base_meta = {
            "processed_id": pid,
            "unique_path": upath,
            "base_context": base_ctx,
            **meta,
        }

        v_prompt = j.get("prompt_embedding")
        if "prompt" in plan and _vec_dim(v_prompt) is not None:
            per_kind_vectors["prompt"].append({"id": pid, "values": v_prompt, "metadata": base_meta})

        v_clip = j.get("clip_embedding")
        if "clip" in plan and _vec_dim(v_clip) is not None:
            per_kind_vectors["clip"].append({"id": pid, "values": v_clip, "metadata": base_meta})

        v_ctx = j.get("context_embedding")
        if "context" in plan and _vec_dim(v_ctx) is not None:
            per_kind_vectors["context"].append({"id": pid, "values": v_ctx, "metadata": base_meta})

    # Upsert per kind in batches
    for kind, vectors in per_kind_vectors.items():
        if not vectors:
            _log(f"  {kind}: 0 vectors (empty)")
            continue
        _, namespace = plan[kind]
        _log(f"  {kind}: upserting {len(vectors)} vectors to namespace=’{namespace}’")

        for batch in _chunked(vectors, UPSERT_BATCH):
            index.upsert(vectors=batch, namespace=namespace)  # per docs examples
            counts[kind] += len(batch)

    _log(f"Upsert complete: {counts}")
    return {
        "index_plan": plan,
        "index_name": PINECONE_INDEX_NAME,
        "index_dimension": index_dim,
        "dims": {"prompt": prompt_dim, "clip": clip_dim, "context": context_dim},
        "skipped_modalities": skipped_modalities,
        "upserted": counts,
    }
