from unittest.mock import MagicMock, patch

from app.services.dashscope_http_embedding import DashScopeHTTPEmbedding


def test_request_embeddings_sorts_by_text_index():
    model = DashScopeHTTPEmbedding(model_name="text-embedding-v4", api_key="k")

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

    with patch("app.services.dashscope_http_embedding.requests.post", return_value=mock_resp):
        vectors = model._request_embeddings(["a", "b"])

    assert vectors == [[1.0, 1.0], [2.0, 2.0]]
