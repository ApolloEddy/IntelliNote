from typing import Any

try:
    import fitz  # type: ignore
except Exception:  # pragma: no cover - runtime guard when pymupdf is not installed
    fitz = None


def extract_pdf_page_preview(file_path: str, page_number: int, max_chars: int = 4000) -> dict[str, Any]:
    if fitz is None:
        raise RuntimeError("PyMuPDF is required for PDF preview. Please install PyMuPDF.")

    pdf = fitz.open(file_path)
    try:
        if page_number < 1 or page_number > pdf.page_count:
            raise ValueError(f"Page out of range: {page_number}/{pdf.page_count}")

        page = pdf.load_page(page_number - 1)
        text = (page.get_text("text") or "").strip()
        if max_chars > 0 and len(text) > max_chars:
            text = text[:max_chars] + "..."

        page_area = float(page.rect.width * page.rect.height)
        image_area = 0.0
        if page_area > 0:
            for image in page.get_images(full=True):
                xref = image[0]
                try:
                    rects = page.get_image_rects(xref)
                except Exception:
                    rects = []
                for rect in rects:
                    image_area += max(0.0, float(rect.width * rect.height))
        image_ratio = max(0.0, min(1.0, image_area / page_area)) if page_area > 0 else 0.0

        return {
            "page_number": page_number,
            "total_pages": int(pdf.page_count),
            "text": text,
            "char_count": len(text),
            "image_ratio": round(image_ratio, 4),
        }
    finally:
        pdf.close()
