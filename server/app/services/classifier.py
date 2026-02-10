import asyncio
import os

from llama_index.core import Settings
from llama_index.core.llms import ChatMessage, MessageRole

from app.core.prompts import prompts
from app.core.taxonomy import NOTEBOOK_TAXONOMY, TAXONOMY_LIST_STR


def _is_dashscope_network_error(exc: Exception) -> bool:
    if isinstance(exc, asyncio.TimeoutError):
        return True
    text = str(exc).lower()
    if "dashscope.aliyuncs.com" not in text and "aliyuncs.com" not in text:
        return False
    markers = ("cannot connect", "max retries exceeded", "ssl", "eof", "connection", "timed out", "sockshttpsconnectionpool")
    return any(m in text for m in markers)


def _add_dashscope_no_proxy():
    base = os.environ.get("NO_PROXY", "")
    parts = [p.strip() for p in base.split(",") if p.strip()]
    for host in ("aliyuncs.com", "dashscope.aliyuncs.com"):
        if host not in parts:
            parts.append(host)
    merged = ",".join(parts)
    os.environ["NO_PROXY"] = merged
    os.environ["no_proxy"] = merged


def _clear_proxy_env():
    for key in ("HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"):
        os.environ.pop(key, None)


def _is_force_no_proxy() -> bool:
    val = os.environ.get("DASHSCOPE_FORCE_NO_PROXY", "")
    return val.lower() in ("1", "true", "yes", "on")


async def _run_with_dashscope_fallback(func):
    timeout_s = 12
    old_env = {k: os.environ.get(k) for k in (
        "NO_PROXY", "no_proxy",
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
    )}
    if _is_force_no_proxy():
        try:
            _clear_proxy_env()
            _add_dashscope_no_proxy()
            return await asyncio.wait_for(asyncio.to_thread(func), timeout=timeout_s)
        except Exception as e:
            if not _is_dashscope_network_error(e):
                raise
            return await asyncio.wait_for(asyncio.to_thread(func), timeout=timeout_s)
        finally:
            for key, value in old_env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value

    try:
        return await asyncio.wait_for(asyncio.to_thread(func), timeout=timeout_s)
    except Exception as e:
        if not _is_dashscope_network_error(e):
            raise

        try:
            _add_dashscope_no_proxy()
            try:
                return await asyncio.wait_for(asyncio.to_thread(func), timeout=timeout_s)
            except Exception as e2:
                if not _is_dashscope_network_error(e2):
                    raise
                _clear_proxy_env()
                _add_dashscope_no_proxy()
                return await asyncio.wait_for(asyncio.to_thread(func), timeout=timeout_s)
        finally:
            for key, value in old_env.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


def _extract_response_text(response) -> str:
    if response is None:
        return ""
    message = getattr(response, "message", None)
    if message is not None:
        content = getattr(message, "content", None)
        if isinstance(content, str) and content.strip():
            return content
    for attr in ("response", "text", "content"):
        value = getattr(response, attr, None)
        if isinstance(value, str) and value.strip():
            return value
    return ""


def _chat_kwargs_for_model(llm) -> dict:
    model_name = str(getattr(llm, "model_name", "")).lower()
    if model_name.startswith("qwen3"):
        return {"enable_thinking": False}
    return {}


def _extract_dashscope_error(response) -> str:
    raw = getattr(response, "raw", None)
    if isinstance(raw, dict):
        code = raw.get("code")
        message = raw.get("message")
        status = raw.get("status_code")
        if code or message:
            return f"{status or ''} {code or ''} {message or ''}".strip()
    return ""


class ClassifierService:
    def __init__(self):
        self.llm = Settings.llm
        self.taxonomy = NOTEBOOK_TAXONOMY
        self.taxonomy_list_str = TAXONOMY_LIST_STR

    async def classify_text(self, text_content: str) -> str:
        """
        Classifies the text content and returns the corresponding Emoji.
        """
        if not text_content or len(text_content.strip()) < 10:
            return self.taxonomy.get("unknown", "❓")

        # Truncate text to avoid token limits (e.g., first 2000 chars)
        truncated_text = text_content[:2000]

        prompt_str = prompts.classification.replace(
            "{{ taxonomy_list }}", self.taxonomy_list_str
        ).replace(
            "{{ text_content }}", truncated_text
        )

        messages = [
            ChatMessage(role=MessageRole.USER, content=prompt_str)
        ]

        try:
            # Use sync chat in a worker thread with proxy/no-proxy fallback.
            chat_kwargs = _chat_kwargs_for_model(self.llm)
            response = await _run_with_dashscope_fallback(lambda: self.llm.chat(messages, **chat_kwargs))
            content = _extract_response_text(response)

            if not content:
                err = _extract_dashscope_error(response)
                if err:
                    print(f"Classification warning: {err}")
                else:
                    print("Classification warning: Empty response from LLM")
                return self.taxonomy.get("general", "📁")

            category = content.strip().lower()
            
            # Clean up potential markdown formatting or quotes
            category = category.replace("`", "").replace('"', "").replace("'", "")
            
            # Fallback for complex output (take the first line or first word)
            if "\n" in category:
                category = category.split("\n")[0].strip()
            
            return self.taxonomy.get(category, self.taxonomy.get("general", "📁"))
            
        except Exception as e:
            print(f"Classification failed: {e}")
            return self.taxonomy.get("general", "📁")

classifier_service = ClassifierService()
