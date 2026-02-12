import base64
from abc import ABC, abstractmethod
from dataclasses import dataclass
from pathlib import Path
from typing import List, Optional, Tuple

import requests
from llama_index.core import Document as LlamaDocument
from llama_index.core import SimpleDirectoryReader

from app.core.config import settings

try:
    import fitz  # type: ignore
except Exception:  # pragma: no cover - import guard for environments without pymupdf
    fitz = None

SUPPORTED_DOCUMENT_EXTENSIONS = {".txt", ".md", ".pdf"}


@dataclass
class ParseStats:
    parser: str
    total_pages: int = 0
    text_pages: int = 0
    ocr_pages: int = 0
    skipped_pages: int = 0

    def to_detail(self) -> dict:
        return {
            "parser": self.parser,
            "total_pages": self.total_pages,
            "text_pages": self.text_pages,
            "ocr_pages": self.ocr_pages,
            "skipped_pages": self.skipped_pages,
        }


class BaseDocumentParser(ABC):
    name: str = "base"

    @abstractmethod
    def parse(self, file_path: str, filename: str) -> Tuple[List[LlamaDocument], ParseStats]:
        raise NotImplementedError


class TextDocumentParser(BaseDocumentParser):
    name = "simple_reader"

    def parse(self, file_path: str, filename: str) -> Tuple[List[LlamaDocument], ParseStats]:
        reader = SimpleDirectoryReader(input_files=[file_path])
        docs = reader.load_data()
        stats = ParseStats(
            parser=self.name,
            total_pages=max(1, len(docs)),
            text_pages=len(docs),
            ocr_pages=0,
            skipped_pages=0,
        )
        return docs, stats


class BasePdfOcrProvider(ABC):
    @abstractmethod
    def enabled(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def extract_text(self, image_png_bytes: bytes, page_number: int) -> str:
        raise NotImplementedError


class DashScopeQwenOcrProvider(BasePdfOcrProvider):
    """
    OCR fallback provider for scanned PDF pages.
    Uses Qwen-VL via DashScope multimodal endpoint.
    """

    _url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"

    def __init__(self):
        self._model_name = settings.PDF_OCR_MODEL_NAME
        self._api_key = settings.DASHSCOPE_LLM_API_KEY or settings.DASHSCOPE_API_KEY or ""

    def enabled(self) -> bool:
        return settings.PDF_OCR_ENABLED and bool(self._api_key)

    def extract_text(self, image_png_bytes: bytes, page_number: int) -> str:
        if not self.enabled():
            return ""

        prompt = (
            "请将这页 PDF 图片中的可读文本按原始顺序完整提取为纯文本。"
            "不要总结，不要补充，不要解释。"
        )
        image_data = base64.b64encode(image_png_bytes).decode("ascii")
        payload = {
            "model": self._model_name,
            "input": {
                "messages": [
                    {
                        "role": "user",
                        "content": [
                            {"image": f"data:image/png;base64,{image_data}"},
                            {"text": prompt},
                        ],
                    }
                ]
            },
            "parameters": {"result_format": "message", "temperature": 0.0},
        }
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }

        try:
            timeout_s = max(10, int(settings.PDF_OCR_TIMEOUT_SECONDS))
            resp = requests.post(self._url, headers=headers, json=payload, timeout=timeout_s)
            body = resp.json() if resp.content else {}
            if resp.status_code != 200:
                code = body.get("code", "") if isinstance(body, dict) else ""
                msg = body.get("message", "") if isinstance(body, dict) else ""
                print(f"[PDF OCR] Page {page_number} failed: HTTP {resp.status_code} {code} {msg}")
                return ""
            return self._extract_text(body).strip()
        except Exception as exc:
            print(f"[PDF OCR] Page {page_number} request failed: {exc}")
            return ""

    def _extract_text(self, body: dict) -> str:
        try:
            choices = body.get("output", {}).get("choices", [])
            if not choices:
                return ""
            message = choices[0].get("message", {})
            content = message.get("content")
            if isinstance(content, str):
                return content
            if isinstance(content, dict):
                text = content.get("text")
                return text if isinstance(text, str) else ""
            if isinstance(content, list):
                parts: List[str] = []
                for item in content:
                    if isinstance(item, str):
                        parts.append(item)
                        continue
                    if isinstance(item, dict):
                        text = item.get("text")
                        if isinstance(text, str):
                            parts.append(text)
                return "\n".join(part for part in parts if part.strip())
        except Exception:
            return ""
        return ""


class PdfDocumentParser(BaseDocumentParser):
    name = "pdf_hybrid"

    def __init__(self, ocr_provider: Optional[BasePdfOcrProvider] = None):
        self._ocr_provider = ocr_provider

    def parse(self, file_path: str, filename: str) -> Tuple[List[LlamaDocument], ParseStats]:
        if fitz is None:
            raise RuntimeError("PyMuPDF is required for PDF parsing. Please install PyMuPDF.")

        pdf = fitz.open(file_path)
        docs: List[LlamaDocument] = []
        stats = ParseStats(parser=self.name, total_pages=pdf.page_count)

        for page_index in range(pdf.page_count):
            page = pdf.load_page(page_index)
            page_number = page_index + 1
            raw_text = (page.get_text("text") or "").strip()
            image_ratio = self._estimate_image_ratio(page)
            used_ocr = False
            text = raw_text

            if not self._looks_like_text_page(raw_text) and self._should_try_ocr(raw_text, image_ratio, page_number):
                rendered = self._render_page_png(page)
                text = self._ocr_provider.extract_text(rendered, page_number).strip() if rendered else ""
                used_ocr = bool(text)

            if not text.strip():
                stats.skipped_pages += 1
                continue

            if used_ocr:
                stats.ocr_pages += 1
            else:
                stats.text_pages += 1

            docs.append(
                LlamaDocument(
                    text=text,
                    metadata={
                        "page_number": page_number,
                        "source_parser": self.name,
                        "ocr_used": used_ocr,
                        "image_ratio": round(image_ratio, 4),
                    },
                )
            )

        if not docs:
            raise RuntimeError("No readable text extracted from PDF.")

        return docs, stats

    def _looks_like_text_page(self, text: str) -> bool:
        min_chars = max(1, int(settings.PDF_TEXT_PAGE_MIN_CHARS))
        return len(text.strip()) >= min_chars

    def _should_try_ocr(self, text: str, image_ratio: float, page_number: int) -> bool:
        if not self._ocr_provider or not self._ocr_provider.enabled():
            return False
        if page_number > max(1, int(settings.PDF_OCR_MAX_PAGES)):
            return False
        max_text_chars = max(0, int(settings.PDF_SCAN_PAGE_MAX_CHARS))
        threshold = max(0.0, min(1.0, float(settings.PDF_SCAN_IMAGE_RATIO_THRESHOLD)))
        return len(text.strip()) <= max_text_chars and image_ratio >= threshold

    def _render_page_png(self, page) -> bytes:
        pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), alpha=False)
        return pix.tobytes("png")

    def _estimate_image_ratio(self, page) -> float:
        page_area = float(page.rect.width * page.rect.height)
        if page_area <= 0:
            return 0.0
        image_area = 0.0
        for image in page.get_images(full=True):
            xref = image[0]
            try:
                rects = page.get_image_rects(xref)
            except Exception:
                rects = []
            for rect in rects:
                image_area += max(0.0, float(rect.width * rect.height))
        return max(0.0, min(1.0, image_area / page_area))


class DocumentParserRegistry:
    def __init__(self):
        self._text_parser = TextDocumentParser()
        self._pdf_parser = PdfDocumentParser(ocr_provider=DashScopeQwenOcrProvider())

    def parse(self, file_path: str, filename: str) -> Tuple[List[LlamaDocument], ParseStats]:
        ext = Path(filename or "").suffix.lower()
        if ext == ".pdf":
            return self._pdf_parser.parse(file_path=file_path, filename=filename)
        if ext in {".txt", ".md"}:
            return self._text_parser.parse(file_path=file_path, filename=filename)
        raise RuntimeError(f"Unsupported file extension for parser registry: {ext or 'unknown'}")

    @staticmethod
    def is_supported(filename: str) -> bool:
        ext = Path(filename or "").suffix.lower()
        return ext in SUPPORTED_DOCUMENT_EXTENSIONS
