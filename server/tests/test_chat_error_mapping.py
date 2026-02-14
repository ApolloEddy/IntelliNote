from app.api.endpoints.chat import _classify_llm_error


def test_classify_llm_timeout_error():
    code, message = _classify_llm_error("primary: Read timed out. (read timeout=20)")
    assert code == "E_LLM_TIMEOUT"
    assert "超时" in message


def test_classify_llm_network_error():
    code, message = _classify_llm_error("proxy_off: HTTPSConnectionPool ... Connection refused")
    assert code == "E_LLM_NETWORK"
    assert "网络" in message


def test_classify_llm_auth_error():
    code, message = _classify_llm_error("primary: HTTP 401 Unauthorized")
    assert code == "E_LLM_AUTH"
    assert "鉴权" in message

