import asyncio
import os
from typing import Any, List

import requests
from llama_index.core.base.embeddings.base import BaseEmbedding


class DashScopeHTTPEmbedding(BaseEmbedding):
    """
    DashScope embedding client based on direct HTTP requests.
    Avoids SDK internal concurrent-per-text behavior that may be unstable in some proxy/TUN networks.
    """

    model_name: str
    api_key: str
    timeout_seconds: int = 60

    @staticmethod
    def _is_force_no_proxy() -> bool:
        val = os.environ.get("DASHSCOPE_FORCE_NO_PROXY", "")
        return val.lower() in ("1", "true", "yes", "on")

    def _request_embeddings(self, texts: List[str]) -> List[List[float]]:
        if not texts:
            return []

        url = "https://dashscope.aliyuncs.com/api/v1/services/embeddings/text-embedding/text-embedding"
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json",
        }
        payload = {
            "model": self.model_name,
            "input": {"texts": texts},
        }

        def _post():
            kwargs = {"headers": headers, "json": payload, "timeout": self.timeout_seconds}
            if self._is_force_no_proxy():
                kwargs["proxies"] = {"http": None, "https": None}
            return requests.post(url, **kwargs)

        try:
            response = _post()
        except Exception as e:
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
        body: Any = response.json()
        embeddings = body.get("output", {}).get("embeddings", []) if isinstance(body, dict) else []
        if not embeddings:
            raise ValueError(f"DashScope embedding response missing embeddings: {body}")

        embeddings_sorted = sorted(embeddings, key=lambda item: item.get("text_index", 0))
        vectors = [item.get("embedding") for item in embeddings_sorted]
        if any(v is None for v in vectors):
            raise ValueError(f"DashScope embedding response has empty vector: {body}")
        return vectors

    def _get_query_embedding(self, query: str) -> List[float]:
        return self._request_embeddings([query])[0]

    async def _aget_query_embedding(self, query: str) -> List[float]:
        return await asyncio.to_thread(self._get_query_embedding, query)

    def _get_text_embedding(self, text: str) -> List[float]:
        return self._request_embeddings([text])[0]

    def _get_text_embeddings(self, texts: List[str]) -> List[List[float]]:
        return self._request_embeddings(texts)

    async def _aget_text_embedding(self, text: str) -> List[float]:
        return await asyncio.to_thread(self._get_text_embedding, text)

    async def _aget_text_embeddings(self, texts: List[str]) -> List[List[float]]:
        return await asyncio.to_thread(self._get_text_embeddings, texts)
