# ImagePineconeFetch.py
from __future__ import annotations

import os
import json
import time as _time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import numpy as np

from dotenv import load_dotenv


def _log(msg: str) -> None:
    ts = _time.strftime("%H:%M:%S")
    print(f"[{ts}][PineconeFetch] {msg}", flush=True)

from pinecone.grpc import PineconeGRPC as Pinecone

# Embedders
from sentence_transformers import SentenceTransformer
import torch
from transformers import AutoProcessor, AutoModel


# ------------------------------------------------------------
# .env load (same pattern as your save script)
# Put .env next to this file unless you change the path.
# ------------------------------------------------------------
load_dotenv(dotenv_path=Path(__file__).resolve().parent / ".env")


# ------------------------------------------------------------
# ENV SETTINGS
# ------------------------------------------------------------
PINECONE_API_KEY = os.getenv("PINECONE_API_KEY") or os.getenv("Pinecone-API-Key", "")
PINECONE_INDEX_NAME = os.getenv("PINECONE_INDEX_NAME", "lesson-images")


# ------------------------------------------------------------
# MODELS
# ------------------------------------------------------------
MINILM_NAME = os.getenv("MINILM_NAME", "all-MiniLM-L6-v2")
SIGLIP_NAME = os.getenv("SIGLIP_NAME", "google/siglip2-giant-opt-patch16-384")


# ------------------------------------------------------------
# INTERNAL CACHES (so repeated calls don't reload models)
# ------------------------------------------------------------
_minilm_model: Optional[SentenceTransformer] = None
_siglip_processor: Optional[Any] = None
_siglip_model: Optional[Any] = None
_siglip_device: Optional[torch.device] = None
_pc: Optional[Pinecone] = None
_opened_indexes: Dict[str, Any] = {}
_plan_cache: Dict[Tuple[int, int, int, int], Dict[str, Tuple[str, str]]] = {}

import threading

# ... keep your existing caches ...

# Optional externally-provided (hot) models from ImagePipeline.py
_minilm_tok: Optional[Any] = None
_minilm_trf_model: Optional[Any] = None
_minilm_device: Optional[torch.device] = None

_EMBED_MINILM_LOCK = threading.Lock()
_EMBED_SIGLIP_LOCK = threading.Lock()

def configure_hot_models(*, siglip_bundle: Any = None, minilm_bundle: Any = None) -> None:
    """
    Allows ImagePipeline.py (same process) to inject already-loaded models here,
    so PineconeFetch does NOT reload them.

    Expected bundle shapes:
      - SigLIP bundle: has .model, .processor, .device
      - MiniLM bundle: either sentence-transformers (.model has encode)
        OR transformers (.model + .tokenizer)
    """
    global _siglip_processor, _siglip_model, _siglip_device
    global _minilm_model, _minilm_tok, _minilm_trf_model, _minilm_device

    if siglip_bundle is not None:
        try:
            _siglip_model = siglip_bundle.model
            _siglip_processor = siglip_bundle.processor
            dev = getattr(siglip_bundle, "device", None)
            if isinstance(dev, torch.device):
                _siglip_device = dev
            else:
                _siglip_device = torch.device(str(dev) if dev else ("cuda" if torch.cuda.is_available() else "cpu"))
        except Exception:
            # If injection fails, just keep local lazy-loading behavior
            pass

    if minilm_bundle is not None:
        try:
            # sentence-transformers path
            if getattr(minilm_bundle, "use_sentence_transformers", False) and hasattr(minilm_bundle.model, "encode"):
                _minilm_model = minilm_bundle.model
                _minilm_tok = None
                _minilm_trf_model = None
                _minilm_device = None
            else:
                # transformers path
                _minilm_model = None
                _minilm_trf_model = minilm_bundle.model
                _minilm_tok = minilm_bundle.tokenizer
                dev = getattr(minilm_bundle, "device", None)
                if isinstance(dev, torch.device):
                    _minilm_device = dev
                else:
                    _minilm_device = torch.device(str(dev) if dev else ("cuda" if torch.cuda.is_available() else "cpu"))
        except Exception:
            pass

# ------------------------------------------------------------
# SMALL UTILS
# ------------------------------------------------------------
def _l2_normalize(v: np.ndarray) -> np.ndarray:
    n = np.linalg.norm(v)
    if n <= 0:
        return v
    return v / n


def _vec_dim(v: Any) -> Optional[int]:
    if isinstance(v, list) and v and all(isinstance(x, (int, float)) for x in v):
        return len(v)
    return None


def _open_index(pc: Pinecone, index_name: str):
    desc = pc.describe_index(index_name)
    host = getattr(desc, "host", None)
    if not host and isinstance(desc, dict):
        host = desc.get("host")
    if not host:
        raise RuntimeError(f"Could not resolve host for index: {index_name}")
    return pc.Index(host=host)


def _index_exists(pc: Pinecone, index_name: str) -> bool:
    try:
        pc.describe_index(index_name)
        return True
    except Exception:
        return False
    

def _get_pc() -> Pinecone:
    global _pc
    if _pc is None:
        if not PINECONE_API_KEY:
            raise RuntimeError("PINECONE_API_KEY missing. Put it in .env next to this file.")
        _pc = Pinecone(api_key=PINECONE_API_KEY)
    return _pc

def _get_index(index_name: str):
    global _opened_indexes
    if index_name in _opened_indexes:
        return _opened_indexes[index_name]
    pc = _get_pc()
    if not _index_exists(pc, index_name):
        raise RuntimeError(f"Index not found: {index_name}")
    idx = _open_index(pc, index_name)
    _opened_indexes[index_name] = idx
    return idx


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


def _fixed_index_plan(
    index_dim: int,
    prompt_dim: int,
    clip_dim: int,
    context_dim: int,
) -> Tuple[Dict[str, Tuple[str, str]], Dict[str, str]]:
    dim_map = {"prompt": prompt_dim, "clip": clip_dim, "context": context_dim}
    plan: Dict[str, Tuple[str, str]] = {}
    skipped: Dict[str, str] = {}
    for kind, dim in dim_map.items():
        if int(dim) != int(index_dim):
            skipped[kind] = f"dim_mismatch(vector={dim}, index={index_dim})"
            continue
        plan[kind] = (PINECONE_INDEX_NAME, kind)
    return plan, skipped


def _normalized_weights(
    available_modalities: List[str],
    base_weights: Tuple[float, float, float],
) -> Dict[str, float]:
    base = {
        "prompt": float(base_weights[0]),
        "clip": float(base_weights[1]),
        "context": float(base_weights[2]),
    }
    selected = {k: base[k] for k in available_modalities if k in base}
    total = sum(selected.values())
    if total <= 0:
        n = max(1, len(available_modalities))
        return {k: 1.0 / n for k in available_modalities}
    return {k: v / total for k, v in selected.items()}



# ------------------------------------------------------------
# PLAN
# ------------------------------------------------------------
# ------------------------------------------------------------
# EMBEDDERS
# ------------------------------------------------------------
def _mean_pool(last_hidden: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
    mask = attention_mask.unsqueeze(-1).type_as(last_hidden)
    summed = (last_hidden * mask).sum(dim=1)
    denom = mask.sum(dim=1).clamp(min=1e-9)
    return summed / denom


def embed_minilm(text: str) -> List[float]:
    global _minilm_model, _minilm_tok, _minilm_trf_model, _minilm_device

    # If ImagePipeline injected a hot sentence-transformers model, use it.
    if _minilm_model is not None:
        with _EMBED_MINILM_LOCK:
            vec = _minilm_model.encode([text], normalize_embeddings=True)
        v = np.asarray(vec[0], dtype=np.float32)
        return v.tolist()

    # If ImagePipeline injected a hot transformers model+tokenizer, use it.
    if _minilm_trf_model is not None and _minilm_tok is not None and _minilm_device is not None:
        with _EMBED_MINILM_LOCK, torch.inference_mode():
            inputs = _minilm_tok([text], return_tensors="pt", padding=True, truncation=True)
            inputs = {k: v.to(_minilm_device) for k, v in inputs.items()}
            out = _minilm_trf_model(**inputs)
            pooled = _mean_pool(out.last_hidden_state, inputs["attention_mask"])
            pooled = torch.nn.functional.normalize(pooled, p=2, dim=1)
            feats = pooled[0].detach().cpu().float().numpy().astype(np.float32)
        return feats.tolist()

    # Fallback: local lazy-load (old behavior)
    if _minilm_model is None:
        _minilm_model = SentenceTransformer(MINILM_NAME)

    with _EMBED_MINILM_LOCK:
        vec = _minilm_model.encode([text], normalize_embeddings=True)
    v = np.asarray(vec[0], dtype=np.float32)
    return v.tolist()



def embed_siglip_text(text: str) -> List[float]:
    global _siglip_processor, _siglip_model, _siglip_device

    # If ImagePipeline injected hot SigLIP, use it; otherwise lazy-load locally.
    if _siglip_processor is None or _siglip_model is None or _siglip_device is None:
        _siglip_processor = AutoProcessor.from_pretrained(SIGLIP_NAME)
        _siglip_model = AutoModel.from_pretrained(SIGLIP_NAME)
        _siglip_device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        _siglip_model.to(_siglip_device)
        _siglip_model.eval()

    with _EMBED_SIGLIP_LOCK, torch.inference_mode():
        inputs = _siglip_processor(
            text=[text],
            return_tensors="pt",
            padding=True,
            truncation=True,
        )
        # works for BatchEncoding or dict-like
        try:
            inputs = inputs.to(_siglip_device)
        except Exception:
            inputs = {k: v.to(_siglip_device) for k, v in inputs.items()}

        feats = _siglip_model.get_text_features(**inputs)

    feats = feats[0].detach().cpu().float().numpy()
    feats = _l2_normalize(feats)
    return feats.astype(np.float32).tolist()



# ------------------------------------------------------------
# QUERY + FUSION
# ------------------------------------------------------------
@dataclass
class Match:
    processed_id: str
    score: float
    metadata: Dict[str, Any]


def _extract_matches(res: Any) -> List[Match]:
    """
    Works with:
      - GRPC object response: res.matches
      - dict response: res["matches"]
    """
    matches = []
    raw = None

    if hasattr(res, "matches"):
        raw = res.matches
    elif isinstance(res, dict):
        raw = res.get("matches", [])
    else:
        raw = []

    for m in raw:
        if isinstance(m, dict):
            pid = str(m.get("id", "")).strip()
            sc = float(m.get("score", 0.0))
            md = m.get("metadata", {}) if isinstance(m.get("metadata", {}), dict) else {}
        else:
            pid = str(getattr(m, "id", "")).strip()
            sc = float(getattr(m, "score", 0.0))
            md = getattr(m, "metadata", None)
            md = md if isinstance(md, dict) else {}

        if not pid:
            continue
        matches.append(Match(processed_id=pid, score=sc, metadata=md))

    return matches


def _minmax_norm(scores_by_id: Dict[str, float]) -> Dict[str, float]:
    if not scores_by_id:
        return {}

    vals = list(scores_by_id.values())
    mn = float(min(vals))
    mx = float(max(vals))
    if mx - mn < 1e-9:
        # all equal -> collapse to 1.0
        return {k: 1.0 for k in scores_by_id.keys()}

    return {k: (float(v) - mn) / (mx - mn) for k, v in scores_by_id.items()}


def _query_one(
    idx,
    *,
    namespace: str,
    vector: List[float],
    top_k: int,
) -> List[Match]:
    # Pinecone docs show include_metadata=True usage in Python query examples. :contentReference[oaicite:2]{index=2}
    res = idx.query(
        namespace=namespace,
        vector=vector,
        top_k=int(top_k),
        include_values=False,
        include_metadata=True,
    )
    return _extract_matches(res)


def fetch_best_processed(
    prompt: str,
    *,
    top_k_per_modality: int = 50,
    min_modalities: int = 2,
    return_top_n: int = 5,
    weights: Tuple[float, float, float] = (0.35, 0.40, 0.25),  # (prompt, siglip, context)
) -> Dict[str, Any]:
    """
    Returns:
      {
        "best_processed_id": "processed_12",
        "ranking": [
          {
            "processed_id": "...",
            "final_score": 0.83,
            "hits": 3,
            "scores": {"prompt": 0.7, "clip": 0.9, "context": 0.8},
            "metadata_any": {...}
          },
          ...
        ],
        "used_plan": {...}
      }
    """
    if not PINECONE_API_KEY:
        raise RuntimeError("PINECONE_API_KEY missing. Put it in your .env next to this script.")

    prompt = (prompt or "").strip()
    if not prompt:
        raise ValueError("prompt is empty")

    # 1) Embed query
    q_prompt = embed_minilm(prompt)         # for prompt DB
    q_context = q_prompt                    # context DB is also MiniLM in your pipeline assumption
    q_clip = embed_siglip_text(prompt)      # for siglip/clip DB

    prompt_dim = len(q_prompt)
    context_dim = len(q_context)
    clip_dim = len(q_clip)

    # 2) Open the one configured index and keep only compatible modalities.
    pc = Pinecone(api_key=PINECONE_API_KEY)
    if not _index_exists(pc, PINECONE_INDEX_NAME):
        raise RuntimeError(
            f"Index not found: '{PINECONE_INDEX_NAME}'. "
            "Set PINECONE_INDEX_NAME to an existing index."
        )
    index_dim = _index_dimension(pc, PINECONE_INDEX_NAME)
    plan, skipped_modalities = _fixed_index_plan(index_dim, prompt_dim, clip_dim, context_dim)
    if not plan:
        raise RuntimeError(
            f"No compatible modalities for index '{PINECONE_INDEX_NAME}' "
            f"(index_dim={index_dim}, prompt_dim={prompt_dim}, clip_dim={clip_dim}, context_dim={context_dim})."
        )

    index = _open_index(pc, PINECONE_INDEX_NAME)

    # 3) Query each compatible modality.
    prompt_matches: List[Match] = []
    clip_matches: List[Match] = []
    context_matches: List[Match] = []

    if "prompt" in plan:
        _, ns = plan["prompt"]
        prompt_matches = _query_one(index, namespace=ns, vector=q_prompt, top_k=top_k_per_modality)

    if "clip" in plan:
        _, ns = plan["clip"]
        clip_matches = _query_one(index, namespace=ns, vector=q_clip, top_k=top_k_per_modality)

    if "context" in plan:
        _, ns = plan["context"]
        context_matches = _query_one(index, namespace=ns, vector=q_context, top_k=top_k_per_modality)

    # 5) Build per-modality score dicts
    s_prompt = {m.processed_id: float(m.score) for m in prompt_matches}
    s_clip = {m.processed_id: float(m.score) for m in clip_matches}
    s_ctx = {m.processed_id: float(m.score) for m in context_matches}

    # 6) Normalize within each modality so weights are meaningful
    n_prompt = _minmax_norm(s_prompt)
    n_clip = _minmax_norm(s_clip)
    n_ctx = _minmax_norm(s_ctx)

    available_modalities = list(plan.keys())
    weight_map = _normalized_weights(available_modalities, weights)
    effective_min_modalities = max(1, min(int(min_modalities), len(available_modalities)))

    # 7) Fuse (weighted sum) + enforce overlap requirement
    all_ids = set(n_prompt.keys()) | set(n_clip.keys()) | set(n_ctx.keys())

    fused = []
    meta_by_id: Dict[str, Dict[str, Any]] = {}

    # keep some metadata (whatever modality returned it first)
    for m in prompt_matches + clip_matches + context_matches:
        if m.processed_id not in meta_by_id and isinstance(m.metadata, dict):
            meta_by_id[m.processed_id] = m.metadata

    for pid in all_ids:
        hits = 0
        sp = float(n_prompt.get(pid, 0.0))
        sc = float(n_clip.get(pid, 0.0))
        sx = float(n_ctx.get(pid, 0.0))

        if "prompt" in plan and pid in n_prompt:
            hits += 1
        if "clip" in plan and pid in n_clip:
            hits += 1
        if "context" in plan and pid in n_ctx:
            hits += 1

        if hits < effective_min_modalities:
            continue

        final = (
            weight_map.get("prompt", 0.0) * sp
            + weight_map.get("clip", 0.0) * sc
            + weight_map.get("context", 0.0) * sx
        )

        fused.append({
            "processed_id": pid,
            "final_score": float(final),
            "hits": int(hits),
            "scores": {"prompt": sp, "clip": sc, "context": sx},
            "metadata_any": meta_by_id.get(pid, {}),
        })

    fused.sort(key=lambda x: (x["final_score"], x["hits"]), reverse=True)

    best = fused[0]["processed_id"] if fused else None

    return {
        "best_processed_id": best,
        "ranking": fused[: int(return_top_n)],
        "used_plan": {k: [v[0], v[1]] for k, v in plan.items()},
        "index_name": PINECONE_INDEX_NAME,
        "index_dimension": index_dim,
        "skipped_modalities": skipped_modalities,
        "effective_min_modalities": effective_min_modalities,
        "dims": {"prompt": prompt_dim, "clip": clip_dim, "context": context_dim},
    }

def fetch_processed_ids_for_prompt(
    prompt: str,
    *,
    top_n: int = 2,
    top_k_per_modality: int = 50,
    min_modalities: int = 3,
    min_final_score: float = 0.78,
    require_base_context_match: bool = True,
) -> List[str]:
    """
    Returns [] if not accepted.
    Returns list of processed_ids (length up to top_n) if accepted.
    """
    prompt = (prompt or "").strip()
    if not prompt:
        return []

    _log(f"fetch('{prompt[:60]}') top_n={top_n} min_mod={min_modalities} min_score={min_final_score}")

    # embed prompt twice (minilm prompt+context), and siglip once
    q_prompt = embed_minilm(prompt)
    q_context = q_prompt
    q_clip = embed_siglip_text(prompt)

    prompt_dim = len(q_prompt)
    clip_dim = len(q_clip)
    context_dim = len(q_context)

    pc = _get_pc()
    if not _index_exists(pc, PINECONE_INDEX_NAME):
        _log(f"  Index '{PINECONE_INDEX_NAME}' not found -- returning []")
        return []

    index_dim = _index_dimension(pc, PINECONE_INDEX_NAME)
    dims_key = (prompt_dim, clip_dim, context_dim, index_dim)

    # plan caching
    plan = _plan_cache.get(dims_key)
    if plan is None:
        plan, _ = _fixed_index_plan(index_dim, prompt_dim, clip_dim, context_dim)
        _plan_cache[dims_key] = plan
    if not plan:
        _log(f"  No compatible modalities (index_dim={index_dim}) -- returning []")
        return []

    _log(f"  plan modalities: {list(plan.keys())}  index_dim={index_dim}")

    idx = _get_index(PINECONE_INDEX_NAME)
    prompt_matches: List[Match] = []
    clip_matches: List[Match] = []
    ctx_matches: List[Match] = []

    if "prompt" in plan:
        prompt_matches = _query_one(idx, namespace=plan["prompt"][1], vector=q_prompt, top_k=top_k_per_modality)
    if "clip" in plan:
        clip_matches = _query_one(idx, namespace=plan["clip"][1], vector=q_clip, top_k=top_k_per_modality)
    if "context" in plan:
        ctx_matches = _query_one(idx, namespace=plan["context"][1], vector=q_context, top_k=top_k_per_modality)

    _log(f"  matches: prompt={len(prompt_matches)}, clip={len(clip_matches)}, context={len(ctx_matches)}")

    s_prompt = {m.processed_id: float(m.score) for m in prompt_matches}
    s_clip   = {m.processed_id: float(m.score) for m in clip_matches}
    s_ctx    = {m.processed_id: float(m.score) for m in ctx_matches}

    n_prompt = _minmax_norm(s_prompt)
    n_clip   = _minmax_norm(s_clip)
    n_ctx    = _minmax_norm(s_ctx)

    # keep metadata (first seen)
    meta_by_id: Dict[str, Dict[str, Any]] = {}
    for m in prompt_matches + clip_matches + ctx_matches:
        if m.processed_id not in meta_by_id and isinstance(m.metadata, dict):
            meta_by_id[m.processed_id] = m.metadata

    fused = []
    all_ids = set(n_prompt.keys()) | set(n_clip.keys()) | set(n_ctx.keys())

    # weights: (prompt, siglip, context), normalized to available modalities.
    weight_map = _normalized_weights(list(plan.keys()), (0.35, 0.40, 0.25))
    effective_min_modalities = max(1, min(int(min_modalities), len(plan)))

    prompt_norm = prompt.strip().lower()

    for pid in all_ids:
        hits = 0
        if "prompt" in plan and pid in n_prompt: hits += 1
        if "clip" in plan and pid in n_clip:   hits += 1
        if "context" in plan and pid in n_ctx:    hits += 1
        if hits < effective_min_modalities:
            continue

        sp = float(n_prompt.get(pid, 0.0))
        sc = float(n_clip.get(pid, 0.0))
        sx = float(n_ctx.get(pid, 0.0))
        final = (
            weight_map.get("prompt", 0.0) * sp
            + weight_map.get("clip", 0.0) * sc
            + weight_map.get("context", 0.0) * sx
        )

        md = meta_by_id.get(pid, {}) or {}
        if require_base_context_match:
            bc = str(md.get("base_context", "") or "").strip().lower()
            if bc and bc != prompt_norm:
                continue

        fused.append((float(final), int(hits), pid))

    fused.sort(key=lambda x: (x[0], x[1]), reverse=True)

    if not fused:
        _log(f"  fused candidates: 0 -- returning []")
        return []

    # accept policy: top candidate must pass min_final_score
    if fused[0][0] < float(min_final_score):
        _log(f"  best score {fused[0][0]:.3f} < min_final_score {min_final_score} -- returning []")
        return []

    # return top_n pids that also satisfy score >= min_final_score
    out: List[str] = []
    for final, hits, pid in fused:
        if final < float(min_final_score):
            continue
        out.append(pid)
        if len(out) >= int(top_n):
            break

    _log(f"  returning {len(out)} id(s): {out}")
    return out



# ------------------------------------------------------------
# CLI quick test
# ------------------------------------------------------------
if __name__ == "__main__":
    import sys
    q = " ".join(sys.argv[1:]).strip()
    if not q:
        print("Usage: python ImagePineconeFetch.py \"your image prompt here\"")
        raise SystemExit(2)

    res = fetch_best_processed(q, top_k_per_modality=50, min_modalities=2, return_top_n=5)
    print(json.dumps(res, indent=2, ensure_ascii=False))
