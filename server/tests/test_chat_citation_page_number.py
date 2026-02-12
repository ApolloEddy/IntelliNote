from unittest.mock import MagicMock

from app.api.endpoints.chat import _build_citations


def _build_mock_node(page_number):
    hit = MagicMock()
    hit.score = 0.91
    hit.node = MagicMock()
    hit.node.node_id = "chunk-1"
    hit.node.metadata = {
        "source_file_id": "doc-1",
        "page_number": page_number,
    }
    hit.node.get_content.return_value = "Citation content."
    return hit


def test_build_citations_includes_numeric_page_number():
    citations = _build_citations([_build_mock_node("3")])
    assert citations[0]["page_number"] == 3


def test_build_citations_keeps_page_number_none_for_invalid_value():
    citations = _build_citations([_build_mock_node("N/A")])
    assert citations[0]["page_number"] is None

