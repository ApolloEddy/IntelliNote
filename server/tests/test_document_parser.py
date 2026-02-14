import pytest

fitz = pytest.importorskip("fitz")

from app.services.document_parser import (
    BasePdfOcrProvider,
    BasePdfVisionProvider,
    DocumentParserRegistry,
    ParsedPageImage,
    PdfDocumentParser,
)


def _build_text_pdf(path: str) -> None:
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((72, 80), "PDF parser smoke test.\nThis page contains text.")
    doc.save(path)
    doc.close()


def _build_blank_pdf(path: str) -> None:
    doc = fitz.open()
    doc.new_page()
    doc.save(path)
    doc.close()


def _build_two_column_pdf(path: str) -> None:
    doc = fitz.open()
    page = doc.new_page()
    page.insert_text((72, 80), "LEFT TOP")
    page.insert_text((72, 120), "LEFT BOTTOM")
    page.insert_text((320, 80), "RIGHT TOP")
    page.insert_text((320, 120), "RIGHT BOTTOM")
    doc.save(path)
    doc.close()


class _StubOcrProvider(BasePdfOcrProvider):
    def __init__(self, text: str):
        self._text = text

    def enabled(self) -> bool:
        return True

    def extract_text(self, image_png_bytes: bytes, page_number: int) -> str:
        return self._text


class _StubVisionProvider(BasePdfVisionProvider):
    def __init__(self, outputs: list[str]):
        self._outputs = list(outputs)

    def enabled(self) -> bool:
        return True

    def describe_image(self, image_png_bytes: bytes, page_number: int, image_index: int) -> str:
        if not self._outputs:
            return ""
        return self._outputs.pop(0)


def test_pdf_parser_extracts_page_metadata(tmp_path):
    pdf_path = tmp_path / "sample.pdf"
    _build_text_pdf(str(pdf_path))

    parser = PdfDocumentParser(ocr_provider=None, vision_provider=None)
    docs, stats = parser.parse(str(pdf_path), "sample.pdf")

    assert len(docs) == 1
    assert docs[0].metadata["page_number"] == 1
    assert docs[0].metadata["ocr_used"] is False
    assert docs[0].metadata["vision_used"] is False
    assert docs[0].metadata["vision_images"] == 0
    assert stats.total_pages == 1
    assert stats.text_pages == 1
    assert stats.ocr_pages == 0
    assert stats.vision_pages == 0
    assert stats.vision_images == 0
    assert stats.skipped_pages == 0


def test_document_parser_registry_routes_pdf(tmp_path):
    pdf_path = tmp_path / "route.pdf"
    _build_text_pdf(str(pdf_path))

    registry = DocumentParserRegistry()
    docs, stats = registry.parse(str(pdf_path), "route.pdf")

    assert len(docs) == 1
    assert stats.parser == "pdf_hybrid"


def test_pdf_parser_adds_vision_summary_for_text_page(tmp_path, monkeypatch):
    pdf_path = tmp_path / "vision_text.pdf"
    _build_text_pdf(str(pdf_path))

    parser = PdfDocumentParser(
        ocr_provider=None,
        vision_provider=_StubVisionProvider(["这是一张网络结构示意图，展示输入层到分类层的连接关系。"]),
    )
    monkeypatch.setattr(
        parser,
        "_collect_page_images",
        lambda page: ([ParsedPageImage(png_bytes=b"fake-image", area_ratio=0.3)], 0.3),
    )

    docs, stats = parser.parse(str(pdf_path), "vision_text.pdf")

    assert len(docs) == 1
    assert "图像理解补充" in docs[0].text
    assert docs[0].metadata["vision_used"] is True
    assert docs[0].metadata["vision_images"] == 1
    assert stats.text_pages == 1
    assert stats.vision_pages == 1
    assert stats.vision_images == 1


def test_pdf_parser_uses_ocr_and_vision_for_scan_page(tmp_path, monkeypatch):
    pdf_path = tmp_path / "scan_page.pdf"
    _build_blank_pdf(str(pdf_path))

    parser = PdfDocumentParser(
        ocr_provider=_StubOcrProvider("OCR extracted text from scanned page."),
        vision_provider=_StubVisionProvider(["图像显示卷积层与池化层交替堆叠。"]),
    )
    monkeypatch.setattr(
        parser,
        "_collect_page_images",
        lambda page: ([ParsedPageImage(png_bytes=b"scan-image", area_ratio=0.92)], 0.92),
    )

    docs, stats = parser.parse(str(pdf_path), "scan_page.pdf")

    assert len(docs) == 1
    assert "OCR extracted text" in docs[0].text
    assert "图像理解补充" in docs[0].text
    assert docs[0].metadata["ocr_used"] is True
    assert docs[0].metadata["vision_used"] is True
    assert stats.ocr_pages == 1
    assert stats.vision_pages == 1


def test_pdf_parser_reorders_two_column_text(tmp_path):
    pdf_path = tmp_path / "two_col.pdf"
    _build_two_column_pdf(str(pdf_path))

    parser = PdfDocumentParser(ocr_provider=None, vision_provider=None)
    docs, _ = parser.parse(str(pdf_path), "two_col.pdf")

    assert len(docs) == 1
    text = docs[0].text
    left_top_idx = text.find("LEFT TOP")
    left_bottom_idx = text.find("LEFT BOTTOM")
    right_top_idx = text.find("RIGHT TOP")
    right_bottom_idx = text.find("RIGHT BOTTOM")

    assert left_top_idx != -1
    assert left_bottom_idx != -1
    assert right_top_idx != -1
    assert right_bottom_idx != -1
    assert left_top_idx < left_bottom_idx < right_top_idx < right_bottom_idx


def test_pdf_parser_vision_whole_page_fallback_for_vector_like_text_page(tmp_path, monkeypatch):
    pdf_path = tmp_path / "vector_like.pdf"
    _build_text_pdf(str(pdf_path))

    parser = PdfDocumentParser(
        ocr_provider=None,
        vision_provider=_StubVisionProvider(["检测到结构图中的多级模块关系。"]),
    )
    monkeypatch.setattr(parser, "_collect_page_images", lambda page: ([], 0.0))
    monkeypatch.setattr(parser, "_estimate_vector_graphics", lambda page: (0.12, 16))

    docs, stats = parser.parse(str(pdf_path), "vector_like.pdf")

    assert len(docs) == 1
    assert "图像理解补充" in docs[0].text
    assert docs[0].metadata["vision_used"] is True
    assert docs[0].metadata["vision_images"] == 1
    assert stats.vision_pages == 1
