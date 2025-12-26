---
name: "Plan: Parallel Image Research → SigLIP Embedding → Pinecone → Whiteboard"
overview: ""
todos:
  - id: todo-1765717922281-lxdr7j22k
    content: Resolve SigLIP model id/dim and Pinecone index config
    status: pending
  - id: todo-1765717922281-6g5bxz5b1
    content: Trigger image research alongside script generation
    status: pending
  - id: todo-1765717922281-zwmqqf2mx
    content: Add SigLIP embed service (image/text) with correct task
    status: pending
  - id: todo-1765717922281-2orqlq2zg
    content: Upsert embeddings into new Pinecone index with metadata
    status: pending
  - id: todo-1765717922281-o5lnrzgvz
    content: Extend script writer to emit image placement (prompt/pos/scale/files)
    status: pending
---

# Plan: Parallel Image Research → SigLIP Embedding → Pinecone → Whiteboard

## Scope

- Trigger image research in parallel with script generation.
- Embed returned images with SigLIP-giant-384 (image→vec now; prep for text→vec later) using the correct inference task.
- Upsert embeddings into a new Pinecone index (name/config TBD from user once provided).
- Extend script writer to emit image placement specs (prompt, position, scale, filenames/metadata) so the frontend whiteboard can sketch them automatically via the existing sketch function.
- Reuse existing pipelines/endpoints where possible; add minimal glue code.

## Steps

1) Confirm model + Pinecone config

- Resolve SigLIP model details for `google/siglip2-giant-opt-patch16-384` (embed task, output dim, pooling/preprocessing) and set to image-to-embedding (not zero-shot classification).
- Define new Pinecone index name/dimension/metric/namespace per user choice; add env/config entries.

2) Wire parallel image research

- Identify the server-side entry where script generation is invoked (likely `lesson_pipeline` orchestrator or `lessons` TutorEngine) and add a parallel call to the `/api/wb/research/search/` endpoint (or direct service) with the existing request context (topic/subject/limit).
- Capture returned image paths/URLs and metadata for embedding.

3) Embedding step with SigLIP-giant-384

- Add a reusable embedding service: load SigLIP-giant-384 once, expose `embed_image(bytes|url)` and `embed_text(text)` for future use; ensure correct preprocessing (384px side, patch size, normalization) and embedding dimension.
- Batch process research results; handle failures gracefully and skip missing/corrupt images.

4) Pinecone upsert

- Initialize Pinecone client from env; create/use the new index with the chosen dimension/metric.
- Upsert embeddings with metadata: source, prompt/subject, image URL/path, any placement hints from the script.
- Provide a query helper for later text→vec searches.

5) Script writer enhancements

- Extend the script writer output schema to include per-image placement requests: desired image prompt/content, position (x,y), scale, target segment/step, and filenames/URLs.
- Ensure this data is passed through existing lesson/timeline structures without breaking clients.

6) Frontend integration handoff

- Document the data contract for the whiteboard: where to read placement + image metadata, and which existing sketch function to call (replacing the current button trigger).
- Note how to fetch the stored image/embedding if needed (URL from research, vector id from Pinecone).

7) Testing & validation

- Unit/functional: mock research → embed → upsert flow; verify Pinecone writes and dimensions.
- Integration: run a lesson generation and confirm images are researched, embedded, and placement metadata is present in the script payload.
- Sanity: ensure model download and env keys are present; fall back cleanly if missing.