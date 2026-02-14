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
    vision_pages: int = 0
    vision_images: int = 0
    skipped_pages: int = 0

    def to_detail(self) -> dict:
        return {
            "parser": self.parser,
            "total_pages": self.total_pages,
            "text_pages": self.text_pages,
            "ocr_pages": self.ocr_pages,
            "vision_pages": self.vision_pages,
            "vision_images": self.vision_images,
            "skipped_pages": self.skipped_pages,
        }


@dataclass
class ParsedPageImage:
    png_bytes: bytes
    area_ratio: float


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


class BasePdfVisionProvider(ABC):
    @abstractmethod
    def enabled(self) -> bool:
        raise NotImplementedError

    @abstractmethod
    def describe_image(self, image_png_bytes: bytes, page_number: int, image_index: int) -> str:
        raise NotImplementedError


def _extract_dashscope_message_text(body: dict) -> str:
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
        return _extract_dashscope_message_text(body)


class DashScopeQwenVisionProvider(BasePdfVisionProvider):
    """
    Vision understanding provider for PDF images.
    Uses Qwen-VL to describe diagrams/charts/figures semantically.
    """

    _url = "https://dashscope.aliyuncs.com/api/v1/services/aigc/multimodal-generation/generation"

    def __init__(self):
        self._model_name = settings.PDF_VISION_MODEL_NAME
        self._api_key = settings.DASHSCOPE_LLM_API_KEY or settings.DASHSCOPE_API_KEY or ""

    def enabled(self) -> bool:
        return settings.PDF_VISION_ENABLED and bool(self._api_key)

    def describe_image(self, image_png_bytes: bytes, page_number: int, image_index: int) -> str:
        if not self.enabled():
            return ""
        prompt = (
            "你是论文图像理解助手。请总结该图像的关键信息，包含："
            "图像类型（流程图/结构图/表格/曲线图等）、核心元素、元素关系、可支持问答的关键信息点。"
            "如果图中有少量文字，可提炼关键术语，但不要逐字 OCR。输出简洁中文段落。"
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
            "parameters": {"result_format": "message", "temperature": 0.1},
        }
        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type": "application/json",
        }

        try:
            timeout_s = max(8, int(settings.PDF_VISION_TIMEOUT_SECONDS))
            resp = requests.post(self._url, headers=headers, json=payload, timeout=timeout_s)
            body = resp.json() if resp.content else {}
            if resp.status_code != 200:
                code = body.get("code", "") if isinstance(body, dict) else ""
                msg = body.get("message", "") if isinstance(body, dict) else ""
                print(
                    f"[PDF Vision] Page {page_number} image {image_index} failed: "
                    f"HTTP {resp.status_code} {code} {msg}"
                )
                return ""
            return _extract_dashscope_message_text(body).strip()
        except Exception as exc:
            print(f"[PDF Vision] Page {page_number} image {image_index} request failed: {exc}")
            return ""


class PdfDocumentParser(BaseDocumentParser):
    name = "pdf_hybrid"

    def __init__(
        self,
        ocr_provider: Optional[BasePdfOcrProvider] = None,
        vision_provider: Optional[BasePdfVisionProvider] = None,
    ):
        self._ocr_provider = ocr_provider
        self._vision_provider = vision_provider

    def parse(self, file_path: str, filename: str) -> Tuple[List[LlamaDocument], ParseStats]:
        if fitz is None:
            raise RuntimeError("PyMuPDF is required for PDF parsing. Please install PyMuPDF.")

        pdf = fitz.open(file_path)
        docs: List[LlamaDocument] = []
        stats = ParseStats(parser=self.name, total_pages=pdf.page_count)

        for page_index in range(pdf.page_count):
            page = pdf.load_page(page_index)
            page_number = page_index + 1
            raw_text = self._extract_page_text(page)
            page_images, image_ratio = self._collect_page_images(page)
            vector_ratio, vector_drawings = self._estimate_vector_graphics(page)
            visual_ratio = max(image_ratio, vector_ratio)
            used_ocr = False
            text = raw_text

            if not self._looks_like_text_page(raw_text) and self._should_try_ocr(raw_text, visual_ratio, page_number):
                rendered = self._render_page_png(page)
                text = self._ocr_provider.extract_text(rendered, page_number).strip() if rendered else ""
                used_ocr = bool(text)

            vision_insights = self._extract_vision_insights(
                page=page,
                page_number=page_number,
                page_images=page_images,
                image_ratio=image_ratio,
                vector_ratio=vector_ratio,
                vector_drawings=vector_drawings,
                used_ocr=used_ocr,
            )
            if vision_insights:
                stats.vision_pages += 1
                stats.vision_images += len(vision_insights)
                vision_text = self._format_vision_insights(vision_insights)
                text = f"{text.strip()}\n\n{vision_text}".strip() if text.strip() else vision_text

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
                        "vision_used": bool(vision_insights),
                        "vision_images": len(vision_insights),
                        "image_ratio": round(image_ratio, 4),
                        "vector_ratio": round(vector_ratio, 4),
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

    def _should_try_vision(self, page_number: int, used_ocr: bool) -> bool:
        if not self._vision_provider or not self._vision_provider.enabled():
            return False
        if page_number > max(1, int(settings.PDF_VISION_MAX_PAGES)):
            return False
        if used_ocr:
            return True
        return bool(settings.PDF_VISION_INCLUDE_TEXT_PAGES)

    def _extract_vision_insights(
        self,
        page,
        page_number: int,
        page_images: List[ParsedPageImage],
        image_ratio: float,
        vector_ratio: float,
        vector_drawings: int,
        used_ocr: bool,
    ) -> List[str]:
        if not self._should_try_vision(page_number=page_number, used_ocr=used_ocr):
            return []

        min_ratio = max(0.0, min(1.0, float(settings.PDF_VISION_MIN_IMAGE_RATIO)))
        max_images = max(1, int(settings.PDF_VISION_MAX_IMAGES_PER_PAGE))
        candidates = [img for img in page_images if img.area_ratio >= min_ratio]

        # Some pages (scan/vector-heavy) may not expose extractable image rects.
        # Fallback to full-page vision to avoid missing diagram semantics.
        should_fallback_whole_page = (
            used_ocr
            or vector_ratio >= (min_ratio * 0.45)
            or vector_drawings >= 10
        )
        if not candidates and should_fallback_whole_page:
            full_page_png = self._render_page_png(page)
            if full_page_png:
                fallback_ratio = max(min_ratio, image_ratio, vector_ratio)
                candidates = [ParsedPageImage(png_bytes=full_page_png, area_ratio=fallback_ratio)]

        insights: List[str] = []
        for idx, image in enumerate(candidates[:max_images], start=1):
            desc = self._vision_provider.describe_image(image.png_bytes, page_number, idx).strip()
            if desc:
                insights.append(desc)
        return insights

    def _format_vision_insights(self, insights: List[str]) -> str:
        lines = ["图像理解补充："]
        for idx, item in enumerate(insights, start=1):
            lines.append(f"- 图像 {idx}: {item}")
        return "\n".join(lines)

    def _render_page_png(self, page) -> bytes:
        pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), alpha=False)
        return pix.tobytes("png")

    def _extract_page_text(self, page) -> str:
        """
        Extract text in a stable reading order for multi-column academic PDFs.
        """
        try:
            blocks = page.get_text("blocks")
        except Exception:
            blocks = []

        text_blocks: List[tuple[float, float, float, float, str]] = []
        for block in blocks:
            if len(block) < 5:
                continue
            x0, y0, x1, y1, text = block[:5]
            normalized = self._normalize_block_text(text if isinstance(text, str) else "")
            if not normalized:
                continue
            text_blocks.append((float(x0), float(y0), float(x1), float(y1), normalized))

        if not text_blocks:
            return (page.get_text("text") or "").strip()

        page_width = max(1.0, float(page.rect.width))
        column_gap_threshold = page_width * 0.18
        columns: List[dict] = []
        for block in sorted(text_blocks, key=lambda item: (item[0], item[1])):
            center_x = (block[0] + block[2]) * 0.5
            matched = None
            for column in columns:
                if abs(float(column["center_x"]) - center_x) <= column_gap_threshold:
                    matched = column
                    break
            if matched is None:
                columns.append({"center_x": center_x, "blocks": [block]})
            else:
                blocks_in_col = matched["blocks"]
                blocks_in_col.append(block)
                matched["center_x"] = sum((b[0] + b[2]) * 0.5 for b in blocks_in_col) / len(blocks_in_col)

        # Too many pseudo-columns usually means noisy layout; fallback to y-major order.
        if len(columns) == 1 or len(columns) > 4:
            merged = sorted(text_blocks, key=lambda item: (item[1], item[0]))
            return "\n\n".join(block[4] for block in merged if block[4].strip()).strip()

        ordered_blocks: List[tuple[float, float, float, float, str]] = []
        for column in sorted(columns, key=lambda item: float(item["center_x"])):
            ordered_blocks.extend(sorted(column["blocks"], key=lambda item: (item[1], item[0])))
        return "\n\n".join(block[4] for block in ordered_blocks if block[4].strip()).strip()

    def _normalize_block_text(self, text: str) -> str:
        lines = [line.strip() for line in (text or "").splitlines() if line.strip()]
        return "\n".join(lines).strip()

    def _collect_page_images(self, page) -> Tuple[List[ParsedPageImage], float]:
        page_area = float(page.rect.width * page.rect.height)
        if page_area <= 0:
            return [], 0.0
        images: List[ParsedPageImage] = []
        seen_rect_keys = set()
        image_area = 0.0
        for image in page.get_images(full=True):
            xref = image[0]
            try:
                rects = page.get_image_rects(xref)
            except Exception:
                rects = []
            for rect in rects:
                rect_area = max(0.0, float(rect.width * rect.height))
                image_area += rect_area
                area_ratio = max(0.0, min(1.0, rect_area / page_area))
                key = (
                    int(xref),
                    round(float(rect.x0), 1),
                    round(float(rect.y0), 1),
                    round(float(rect.x1), 1),
                    round(float(rect.y1), 1),
                )
                if key in seen_rect_keys:
                    continue
                seen_rect_keys.add(key)
                try:
                    pix = page.get_pixmap(matrix=fitz.Matrix(2.0, 2.0), clip=rect, alpha=False)
                    png = pix.tobytes("png")
                    if png:
                        images.append(ParsedPageImage(png_bytes=png, area_ratio=area_ratio))
                except Exception:
                    continue

        page_image_ratio = max(0.0, min(1.0, image_area / page_area))
        return images, page_image_ratio

    def _estimate_vector_graphics(self, page) -> Tuple[float, int]:
        page_area = float(page.rect.width * page.rect.height)
        if page_area <= 0:
            return 0.0, 0
        try:
            drawings = page.get_drawings()
        except Exception:
            drawings = []

        vector_area = 0.0
        drawing_count = 0
        for drawing in drawings:
            drawing_count += 1
            rect = drawing.get("rect")
            if rect is None:
                continue
            try:
                area = max(0.0, float(rect.width * rect.height))
            except Exception:
                area = 0.0
            vector_area += area

        vector_ratio = max(0.0, min(1.0, vector_area / page_area))
        return vector_ratio, drawing_count


class DocumentParserRegistry:
    def __init__(self):
        self._text_parser = TextDocumentParser()
        self._pdf_parser = PdfDocumentParser(
            ocr_provider=DashScopeQwenOcrProvider(),
            vision_provider=DashScopeQwenVisionProvider(),
        )

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
