import os

from app.core.config import Settings


def test_apply_network_settings_sets_proxy_env(monkeypatch):
    monkeypatch.delenv("HTTP_PROXY", raising=False)
    monkeypatch.delenv("HTTPS_PROXY", raising=False)
    monkeypatch.delenv("NO_PROXY", raising=False)

    cfg = Settings(
        HTTP_PROXY="http://127.0.0.1:7890",
        HTTPS_PROXY="http://127.0.0.1:7890",
        NO_PROXY="localhost,127.0.0.1",
    )
    cfg.apply_network_settings()

    assert os.environ["HTTP_PROXY"] == "http://127.0.0.1:7890"
    assert os.environ["HTTPS_PROXY"] == "http://127.0.0.1:7890"
    assert os.environ["NO_PROXY"] == "localhost,127.0.0.1"


def test_apply_network_settings_force_no_proxy(monkeypatch):
    monkeypatch.setenv("NO_PROXY", "localhost")

    cfg = Settings(DASHSCOPE_FORCE_NO_PROXY=True)
    cfg.apply_network_settings()

    no_proxy = os.environ["NO_PROXY"]
    assert "localhost" in no_proxy
    assert "aliyuncs.com" in no_proxy
    assert "dashscope.aliyuncs.com" in no_proxy
