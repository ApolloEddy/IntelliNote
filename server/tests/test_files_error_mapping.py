import os

os.environ.setdefault("OPENAI_API_KEY", "dummy_key")
os.environ.setdefault("DASHSCOPE_API_KEY", "dummy_key")

from app.api.endpoints.files import _classify_ingestion_error


def test_classify_ingestion_queue_error():
    code, hint = _classify_ingestion_error("QUEUE_UNAVAILABLE: redis connection refused")
    assert code == "E_QUEUE_UNAVAILABLE"
    assert "队列" in hint


def test_classify_ingestion_pymupdf_error():
    code, hint = _classify_ingestion_error("PyMuPDF is required for PDF parsing. Please install PyMuPDF.")
    assert code == "E_PDF_DEPENDENCY"
    assert "PyMuPDF" in hint
