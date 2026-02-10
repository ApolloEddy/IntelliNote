import hashlib
import pickle
import asyncio
import os
from typing import List, Dict
import requests
from sqlalchemy import select
from tenacity import retry, stop_after_attempt, wait_fixed, retry_if_exception_type

from llama_index.core.embeddings import BaseEmbedding
from llama_index.core.schema import TextNode
from app.models.chunk_cache import ChunkCache
from app.db.session import AsyncSessionLocal
from app.core.config import settings

class SmartEmbeddingManager:
    def __init__(self, embed_model: BaseEmbedding):
        self.embed_model = embed_model
        self.model_name = settings.EMBED_MODEL_NAME

    def _resolve_embed_api_key(self) -> str:
        """Prefer dedicated embedding key, then fallback to shared key."""
        return settings.DASHSCOPE_EMBED_API_KEY or settings.DASHSCOPE_API_KEY or ""

    def _create_embed_model(self):
        api_key = self._resolve_embed_api_key()
        if not api_key:
            raise ValueError("Missing DashScope embedding API key: set DASHSCOPE_EMBED_API_KEY or DASHSCOPE_API_KEY.")
        from llama_index.embeddings.dashscope import DashScopeEmbedding
        return DashScopeEmbedding(
            model_name=settings.EMBED_MODEL_NAME,
            api_key=api_key
        )

    def _compute_hash(self, text: str) -> str:
        # Normalize text to maximize cache hits (strip whitespace, etc)
        normalized = text.strip().replace("\r\n", "\n")
        return hashlib.sha256(normalized.encode("utf-8")).hexdigest()

    def _iter_batches(self, items: List[str], batch_size: int):
        if batch_size <= 0:
            batch_size = 1
        for i in range(0, len(items), batch_size):
            yield items[i:i + batch_size]

    @staticmethod
    def _is_force_no_proxy() -> bool:
        val = os.environ.get("DASHSCOPE_FORCE_NO_PROXY", "")
        return val.lower() in ("1", "true", "yes", "on")

    def _embed_text_batch_via_http(self, texts: List[str]) -> List[List[float]]:
        """
        Call DashScope embedding endpoint once per batch.
        This avoids the SDK's per-text concurrent calls that can be unstable in some proxy/TUN paths.
        """
        api_key = self._resolve_embed_api_key()
        if not api_key:
            raise ValueError("Missing DashScope embedding API key: set DASHSCOPE_EMBED_API_KEY or DASHSCOPE_API_KEY.")

        url = "https://dashscope.aliyuncs.com/api/v1/services/embeddings/text-embedding/text-embedding"
        headers = {
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": settings.EMBED_MODEL_NAME,
            "input": {"texts": texts},
        }

        def _post():
            kwargs = {"headers": headers, "json": payload, "timeout": 30}
            if self._is_force_no_proxy():
                kwargs["proxies"] = {"http": None, "https": None}
            return requests.post(url, **kwargs)

        try:
            response = _post()
        except Exception as e:
            # One fallback: temporarily bypass proxy for DashScope host.
            text = str(e)
            if "dashscope.aliyuncs.com" not in text:
                raise
            old_no_proxy = os.environ.get("NO_PROXY")
            old_no_proxy_lower = os.environ.get("no_proxy")
            try:
                base = old_no_proxy or ""
                parts = [p.strip() for p in base.split(",") if p.strip()]
                for host in ("aliyuncs.com", "dashscope.aliyuncs.com"):
                    if host not in parts:
                        parts.append(host)
                merged = ",".join(parts)
                os.environ["NO_PROXY"] = merged
                os.environ["no_proxy"] = merged
                response = _post()
            finally:
                if old_no_proxy is None:
                    os.environ.pop("NO_PROXY", None)
                else:
                    os.environ["NO_PROXY"] = old_no_proxy
                if old_no_proxy_lower is None:
                    os.environ.pop("no_proxy", None)
                else:
                    os.environ["no_proxy"] = old_no_proxy_lower

        response.raise_for_status()
        body = response.json()

        embeddings = (
            body.get("output", {}).get("embeddings", [])
            if isinstance(body, dict)
            else []
        )
        if not embeddings:
            raise ValueError(f"DashScope embedding response missing embeddings: {body}")

        # Keep server-returned order by text_index.
        embeddings_sorted = sorted(
            embeddings,
            key=lambda item: item.get("text_index", 0),
        )
        vectors = [item.get("embedding") for item in embeddings_sorted]
        if any(v is None for v in vectors):
            raise ValueError(f"DashScope embedding response has empty vector: {body}")
        return vectors

    async def batch_embed_nodes(self, nodes: List[TextNode], progress_callback=None):
        """
        Main entry point: Takes nodes, fills their embeddings using Cache + API.
        """
        if not nodes:
            return

        # 1. Prepare
        node_map: Dict[str, List[TextNode]] = {} # Hash -> [Nodes] (one hash can map to multiple identical nodes)
        for node in nodes:
            h = self._compute_hash(node.get_content(metadata_mode="embed"))
            if h not in node_map:
                node_map[h] = []
            node_map[h].append(node)
        
        all_hashes = list(node_map.keys())
        needed_hashes = set(all_hashes)
        
        # 2. Check Cache (Async DB)
        async with AsyncSessionLocal() as db:
            # Batch query SQLite
            # SQLite limit is usually 999 vars, so we might need to chunk this query if too huge
            # For simplicity, assuming batch size < 500
            stmt = select(ChunkCache).where(
                ChunkCache.model_name == self.model_name,
                ChunkCache.text_hash.in_(all_hashes),
            )
            result = await db.execute(stmt)
            cached_entries = result.scalars().all()

            for entry in cached_entries:
                embedding = pickle.loads(entry.embedding)
                # Assign to all nodes with this hash
                for node in node_map[entry.text_hash]:
                    node.embedding = embedding
                
                if entry.text_hash in needed_hashes:
                    needed_hashes.remove(entry.text_hash)
        
        # 3. Process Misses (API Call)
        if needed_hashes:
            print(f"Cache Miss: Computing embeddings for {len(needed_hashes)} unique chunks...")
            texts_to_embed = []
            hashes_to_embed = []
            
            # Use one node's content as representative for the hash
            for h in needed_hashes:
                representative_node = node_map[h][0]
                texts_to_embed.append(representative_node.get_content(metadata_mode="embed"))
                hashes_to_embed.append(h)
            
            # Call API in small batches with retry per batch to reduce TLS/proxy instability.
            try:
                @retry(
                    stop=stop_after_attempt(3),
                    wait=wait_fixed(1),
                    retry=retry_if_exception_type(Exception)
                )
                async def _call_api_with_retry(texts):
                    return await asyncio.to_thread(self._embed_text_batch_via_http, texts)

                embeddings = []
                processed = 0
                batch_size = settings.EMBED_BATCH_SIZE
                for text_batch in self._iter_batches(texts_to_embed, batch_size):
                    emb_batch = await _call_api_with_retry(text_batch)
                    embeddings.extend(emb_batch)
                    processed += len(text_batch)
                    if progress_callback:
                        await progress_callback(processed, len(needed_hashes))
            except Exception as e:
                print(f"Embedding API Fatal Error after retries: {e}")
                raise e
            
            # 4. Save new embeddings to Cache
            new_cache_entries = []
            async with AsyncSessionLocal() as db:
                for h, emb in zip(hashes_to_embed, embeddings):
                    # Assign to nodes
                    for node in node_map[h]:
                        node.embedding = emb
                    
                    # Prepare DB record
                    new_cache_entries.append(ChunkCache(
                        text_hash=h,
                        embedding=pickle.dumps(emb),
                        model_name=self.model_name
                    ))
                
                db.add_all(new_cache_entries)
                await db.commit()
