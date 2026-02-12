import asyncio
import json
import os
import time
from typing import List, Optional, Tuple

import requests
from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from llama_index.core import StorageContext, load_index_from_storage
from llama_index.core.vector_stores import MetadataFilter, MetadataFilters
from pydantic import BaseModel

from app.core.config import settings
from app.core.prompts import prompts

router = APIRouter()


def _add_dashscope_no_proxy() -> None:
    base = os.environ.get("NO_PROXY", "")
    parts = [p.strip() for p in base.split(",") if p.strip()]
    for host in ("aliyuncs.com", "dashscope.aliyuncs.com"):
        if host not in parts:
            parts.append(host)
    merged = ",".join(parts)
    os.environ["NO_PROXY"] = merged
    os.environ["no_proxy"] = merged


def _clear_proxy_env() -> None:
    for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        os.environ.pop(key, None)


def _force_no_proxy_enabled() -> bool:
    val = str(os.environ.get("DASHSCOPE_FORCE_NO_PROXY", "")).lower()
    return val in ("1", "true", "yes", "on")


def _resolve_llm_api_key() -> str:
    return settings.DASHSCOPE_LLM_API_KEY or settings.DASHSCOPE_API_KEY or ""


def _build_dashscope_payload(messages: List[dict]) -> dict:
    model_name = settings.LLM_MODEL_NAME
    parameters = {"result_format": "message"}
    # DashScope qwen3 non-streaming calls require this parameter.
    if model_name.lower().startswith("qwen3"):
        parameters["enable_thinking"] = False
    return {
        "model": model_name,
        "input": {"messages": messages},
        "parameters": parameters,
    }


def _extract_dashscope_text(body: dict) -> str:
    try:
        return body["output"]["choices"][0]["message"]["content"] or ""
    except Exception:
        return ""


def _call_dashscope_chat(messages: List[dict]) -> Tuple[str, str]:
    api_key = _resolve_llm_api_key()
    if not api_key:
        return "", "Missing DASHSCOPE LLM API key"

    url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/text-generation/generation"
    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
    }
    payload = _build_dashscope_payload(messages)
    timeout_s = max(10, int(settings.DASHSCOPE_CHAT_TIMEOUT_SECONDS))

    base_env = {k: os.environ.get(k) for k in (
        "NO_PROXY", "no_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
    )}
    attempts = [
        ("primary", _force_no_proxy_enabled(), _force_no_proxy_enabled()),
        ("no_proxy", True, False),
        ("proxy_off", True, True),
    ]
    # Use DASHSCOPE_CHAT_TIMEOUT_SECONDS as the total budget instead of per-attempt timeout.
    started_at = time.monotonic()
    per_attempt_timeout_s = max(5, (timeout_s + len(attempts) - 1) // len(attempts))

    last_error = ""
    for name, use_no_proxy, clear_proxy in attempts:
        try:
            elapsed_s = time.monotonic() - started_at
            remaining_s = timeout_s - elapsed_s
            if remaining_s <= 0:
                break
            request_timeout_s = max(1, min(per_attempt_timeout_s, int(remaining_s)))

            for k, v in base_env.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v

            if clear_proxy:
                _clear_proxy_env()
            if use_no_proxy:
                _add_dashscope_no_proxy()

            req_kwargs = {"headers": headers, "json": payload, "timeout": request_timeout_s}
            if clear_proxy or _force_no_proxy_enabled():
                req_kwargs["proxies"] = {"http": None, "https": None}

            resp = requests.post(url, **req_kwargs)
            body = resp.json() if resp.content else {}
            text = _extract_dashscope_text(body)
            if resp.status_code == 200 and text.strip():
                return text.strip(), ""

            code = body.get("code", "") if isinstance(body, dict) else ""
            msg = body.get("message", "") if isinstance(body, dict) else ""
            last_error = f"{name}: HTTP {resp.status_code} {code} {msg}".strip()
        except Exception as e:
            last_error = f"{name}: {e}"
            print(f"[STREAM] DashScope attempt failed: {last_error}", flush=True)

    if not last_error and (time.monotonic() - started_at) >= timeout_s:
        last_error = f"timeout: exhausted total budget {timeout_s}s"
    return "", last_error or "DashScope request failed"


def get_cached_index(notebook_id: str):
    notebook_path = os.path.join(settings.VECTOR_STORE_DIR, notebook_id)
    if not os.path.exists(notebook_path) or not os.listdir(notebook_path):
        return None
    storage_context = StorageContext.from_defaults(persist_dir=notebook_path)
    return load_index_from_storage(storage_context)


def _dedupe_nodes(nodes) -> list:
    unique = []
    seen = set()
    for n in nodes or []:
        txt = n.node.get_content().strip()
        if txt and txt not in seen:
            unique.append(n)
            seen.add(txt)
    return unique


def _build_citations(nodes) -> List[dict]:
    citations: List[dict] = []
    for n in nodes[:5]:
        raw_page = n.node.metadata.get("page_number")
        page_number = None
        try:
            if raw_page is not None:
                page_number = int(raw_page)
        except (TypeError, ValueError):
            page_number = None

        citations.append(
            {
                "chunk_id": n.node.node_id,
                "source_id": n.node.metadata.get("source_file_id") or n.node.metadata.get("doc_id", "unknown"),
                "text": n.node.get_content(),
                "score": float(getattr(n, "score", 0.0) or 0.0),
                "page_number": page_number,
            }
        )
    return citations


def _build_local_fallback_answer(citations: List[dict]) -> str:
    if not citations:
        return "当前网络不稳定，未能生成完整回答，请稍后重试。"
    lines = ["当前网络不稳定，以下是已检索到的相关资料片段：", ""]
    for idx, c in enumerate(citations[:3], start=1):
        snippet = str(c.get("text", "")).strip().replace("\n", " ")
        if len(snippet) > 180:
            snippet = snippet[:180] + "..."
        page_no = c.get("page_number")
        page_hint = f"(第{page_no}页) " if isinstance(page_no, int) else ""
        lines.append(f"{idx}. {page_hint}{snippet}")
    lines.append("")
    lines.append("你可以继续追问，我会基于这些片段继续回答。")
    return "\n".join(lines)


def _history_to_messages(history: List["Message"] | None) -> List[dict]:
    msgs = []
    for m in history or []:
        role = m.role if m.role in ("system", "user", "assistant") else "user"
        msgs.append({"role": role, "content": m.content})
    return msgs


class Message(BaseModel):
    role: str
    content: str


class ChatRequest(BaseModel):
    notebook_id: str
    question: str
    source_ids: Optional[List[str]] = None
    history: Optional[List[Message]] = None


class StudioRequest(BaseModel):
    notebook_id: str
    type: str


@router.post("/chat/query")
async def query_notebook_stream(request: ChatRequest):
    index = get_cached_index(request.notebook_id)
    use_rag = index is not None and not (isinstance(request.source_ids, list) and len(request.source_ids) == 0)

    async def event_generator():
        print(f"\n[STREAM] Start. Mode: {'RAG' if use_rag else 'GENERAL'}", flush=True)
        history_msgs = _history_to_messages(request.history)

        async def _yield_tokens(text: str):
            chunk_size = 15
            for i in range(0, len(text), chunk_size):
                yield f"data: {json.dumps({'token': text[i:i + chunk_size]})}\n\n"
                await asyncio.sleep(0.01)

        try:
            citations: List[dict] = []
            context_prompt = request.question

            if use_rag:
                filters = None
                if request.source_ids:
                    meta = [MetadataFilter(key=k, value=sid) for sid in request.source_ids for k in ("source_file_id", "doc_id")]
                    filters = MetadataFilters(filters=meta, condition="or")

                def _retrieve():
                    retriever = index.as_retriever(similarity_top_k=15, filters=filters)
                    return retriever.retrieve(request.question)

                try:
                    nodes = await asyncio.to_thread(_retrieve)
                except Exception as e:
                    print(f"[STREAM] Retrieve failed: {e}", flush=True)
                    nodes = []

                unique_nodes = _dedupe_nodes(nodes)
                citations = _build_citations(unique_nodes)
                if citations:
                    print(f"[STREAM] Sending citations: {len(citations)}", flush=True)
                    yield f"data: {json.dumps({'citations': citations})}\n\n"
                    ctx_chunks = []
                    for i, n in enumerate(unique_nodes[:5]):
                        raw_page = n.node.metadata.get("page_number")
                        try:
                            page_no = int(raw_page) if raw_page is not None else None
                        except (TypeError, ValueError):
                            page_no = None
                        page_hint = f"(第{page_no}页) " if page_no is not None else ""
                        ctx_chunks.append(f"[{i+1}] {page_hint}{n.node.get_content()}")
                    ctx = "\n\n".join(ctx_chunks)
                    context_prompt = prompts.chat_rag.format(context_str=ctx, query_str=request.question)

            messages = history_msgs + [{"role": "user", "content": context_prompt}]
            text, err = await asyncio.to_thread(_call_dashscope_chat, messages)

            if text:
                async for t in _yield_tokens(text):
                    yield t
            elif citations:
                # Keep UX alive even when remote generation fails.
                fallback = _build_local_fallback_answer(citations)
                async for t in _yield_tokens(fallback):
                    yield t
            else:
                yield f"data: {json.dumps({'error': err or 'LLM 无响应'})}\n\n"

            yield "data: [DONE]\n\n"
        except Exception as e:
            print(f"[STREAM] Fatal: {e}", flush=True)
            yield f"data: {json.dumps({'error': '服务繁忙，请稍后再试'})}\n\n"

    return StreamingResponse(event_generator(), media_type="text/event-stream")


@router.post("/studio/generate")
async def generate_studio_content(request: StudioRequest):
    index = get_cached_index(request.notebook_id)
    if not index:
        raise HTTPException(status_code=404, detail="Not found")
    try:
        query_engine = index.as_query_engine()
        prompt = prompts.studio_study_guide if request.type == "study_guide" else prompts.studio_quiz
        response = query_engine.query(prompt)
        return {"content": str(response), "type": request.type}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
