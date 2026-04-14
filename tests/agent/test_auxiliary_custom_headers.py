import sys
import types
from unittest.mock import patch

sys.modules.setdefault("openai", types.SimpleNamespace(OpenAI=object))

from agent import auxiliary_client


def test_try_custom_endpoint_includes_runtime_default_headers(monkeypatch):
    monkeypatch.setattr(auxiliary_client, "_resolve_custom_runtime", lambda: ("https://gateway.example.com/api/llm", "test-key"))
    monkeypatch.setattr(auxiliary_client, "_read_main_model", lambda: "gpt-5.4-mini")
    monkeypatch.setenv("THEVIBER_PROJECT_ID", "project-123")
    monkeypatch.setenv("THEVIBER_WORKER_INSTANCE_ID", "worker-456")

    with patch("agent.auxiliary_client.OpenAI") as mock_openai:
        auxiliary_client._try_custom_endpoint()

    assert mock_openai.call_args.kwargs["default_headers"]["X-Theviber-Project-Id"] == "project-123"
    assert (
        mock_openai.call_args.kwargs["default_headers"]["X-Theviber-OpenClaw-Instance-Id"]
        == "worker-456"
    )
