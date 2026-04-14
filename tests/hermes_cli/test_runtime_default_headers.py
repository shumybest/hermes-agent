from hermes_cli.runtime_provider import resolve_runtime_default_headers


def test_resolve_runtime_default_headers_adds_gateway_scope(monkeypatch):
    monkeypatch.setenv("LLM_GATEWAY_APP_ID_HEADER", "X-Custom-App-Id")
    monkeypatch.setenv("LLM_GATEWAY_APP_ID", "project-123")
    monkeypatch.setenv("LLM_GATEWAY_INSTANCE_ID_HEADER", "X-Custom-Worker-Id")
    monkeypatch.setenv("LLM_GATEWAY_INSTANCE_ID", "worker-456")

    headers = resolve_runtime_default_headers("https://gateway.example.com/api/llm")

    assert headers["X-Custom-App-Id"] == "project-123"
    assert headers["X-Custom-Worker-Id"] == "worker-456"


def test_resolve_runtime_default_headers_skips_openrouter(monkeypatch):
    monkeypatch.setenv("LLM_GATEWAY_APP_ID_HEADER", "X-Custom-App-Id")
    monkeypatch.setenv("LLM_GATEWAY_APP_ID", "project-123")

    headers = resolve_runtime_default_headers("https://openrouter.ai/api/v1")

    assert headers == {}
