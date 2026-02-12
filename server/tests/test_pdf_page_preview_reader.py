import pytest

fitz = pytest.importorskip("fitz")

from app.services.pdf_preview import extract_pdf_page_preview


def _build_pdf(path: str) -> None:
    doc = fitz.open()
    page1 = doc.new_page()
    page1.insert_text((72, 80), "Page one text for preview test.")
    page2 = doc.new_page()
    page2.insert_text((72, 80), "Page two text for preview test.")
    doc.save(path)
    doc.close()


def test_extract_pdf_page_preview_returns_expected_fields(tmp_path):
    pdf_path = tmp_path / "preview_sample.pdf"
    _build_pdf(str(pdf_path))

    preview = extract_pdf_page_preview(str(pdf_path), page_number=2, max_chars=200)

    assert preview["page_number"] == 2
    assert preview["total_pages"] == 2
    assert "Page two text" in preview["text"]
    assert preview["char_count"] > 0
    assert 0.0 <= preview["image_ratio"] <= 1.0


def test_extract_pdf_page_preview_rejects_out_of_range_page(tmp_path):
    pdf_path = tmp_path / "preview_range.pdf"
    _build_pdf(str(pdf_path))

    with pytest.raises(ValueError):
        extract_pdf_page_preview(str(pdf_path), page_number=3)
