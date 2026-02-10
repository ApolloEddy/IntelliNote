from unittest.mock import MagicMock, patch

from app.services.smart_embedding import SmartEmbeddingManager


def test_embed_text_batch_via_http_orders_by_text_index(monkeypatch):
    manager = SmartEmbeddingManager(MagicMock())
    monkeypatch.setattr(manager, "_resolve_embed_api_key", lambda: "k")

    mock_resp = MagicMock()
    mock_resp.raise_for_status.return_value = None
    mock_resp.json.return_value = {
        "output": {
            "embeddings": [
                {"text_index": 1, "embedding": [2.0, 2.0]},
                {"text_index": 0, "embedding": [1.0, 1.0]},
            ]
        }
    }

    with patch("app.services.smart_embedding.requests.post", return_value=mock_resp):
        vectors = manager._embed_text_batch_via_http(["a", "b"])

    assert vectors == [[1.0, 1.0], [2.0, 2.0]]
