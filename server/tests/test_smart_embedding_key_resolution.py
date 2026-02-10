from unittest.mock import MagicMock

from app.services.smart_embedding import SmartEmbeddingManager
from app.core.config import settings


def test_resolve_embed_api_key_prefers_embed_key(monkeypatch):
    monkeypatch.setattr(settings, "DASHSCOPE_EMBED_API_KEY", "embed_key")
    monkeypatch.setattr(settings, "DASHSCOPE_API_KEY", "shared_key")
    manager = SmartEmbeddingManager(MagicMock())
    assert manager._resolve_embed_api_key() == "embed_key"


def test_resolve_embed_api_key_falls_back_to_shared_key(monkeypatch):
    monkeypatch.setattr(settings, "DASHSCOPE_EMBED_API_KEY", None)
    monkeypatch.setattr(settings, "DASHSCOPE_API_KEY", "shared_key")
    manager = SmartEmbeddingManager(MagicMock())
    assert manager._resolve_embed_api_key() == "shared_key"


def test_resolve_embed_api_key_empty_when_missing(monkeypatch):
    monkeypatch.setattr(settings, "DASHSCOPE_EMBED_API_KEY", None)
    monkeypatch.setattr(settings, "DASHSCOPE_API_KEY", None)
    manager = SmartEmbeddingManager(MagicMock())
    assert manager._resolve_embed_api_key() == ""
