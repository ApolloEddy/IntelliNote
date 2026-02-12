import pytest

fitz = pytest.importorskip("fitz")

from app.services.document_parser import DocumentParserRegistry, PdfDocumentParser


def _build_text_pdf(path: str) -> None:
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((72, 80), "PDF parser smoke test.\nThis page contains text.")
    doc.save(path)
    doc.close()


def test_pdf_parser_extracts_page_metadata(tmp_path):
    pdf_path = tmp_path / "sample.pdf"
    _build_text_pdf(str(pdf_path))

    parser = PdfDocumentParser(ocr_provider=None)
    docs, stats = parser.parse(str(pdf_path), "sample.pdf")

    assert len(docs) == 1
    assert docs[0].metadata["page_number"] == 1
    assert docs[0].metadata["ocr_used"] is False
    assert stats.total_pages == 1
    assert stats.text_pages == 1
    assert stats.ocr_pages == 0
    assert stats.skipped_pages == 0


def test_document_parser_registry_routes_pdf(tmp_path):
    pdf_path = tmp_path / "route.pdf"
    _build_text_pdf(str(pdf_path))

    registry = DocumentParserRegistry()
    docs, stats = registry.parse(str(pdf_path), "route.pdf")

    assert len(docs) == 1
    assert stats.parser == "pdf_hybrid"

