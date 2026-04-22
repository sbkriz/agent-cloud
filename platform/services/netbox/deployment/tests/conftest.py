"""Shared test fixtures and SDK stubs for discovery worker tests.

The orb-agent runtime modules (worker.backend, worker.models) are not
pip-installable — they're injected by the orb-agent container at runtime.
We stub them here so worker code can be imported in tests.
"""

import sys
import types
from dataclasses import dataclass, field

# ── Stub orb-agent runtime modules ──────────────────────────────────

@dataclass
class StubMetadata:
    name: str = ""
    app_name: str = ""
    app_version: str = ""
    description: str = ""


@dataclass
class StubConfig:
    """Mimics policy.config with attribute access for worker config values."""
    _data: dict = field(default_factory=dict)

    def __getattr__(self, name):
        if name.startswith("_"):
            raise AttributeError(name)
        return self._data.get(name, "")

    def __init__(self, **kwargs):
        object.__setattr__(self, "_data", kwargs)


@dataclass
class StubPolicy:
    config: StubConfig = field(default_factory=StubConfig)
    scope: dict = field(default_factory=dict)


def _install_stubs():
    """Install stub modules for worker.backend and worker.models."""
    backend_mod = types.ModuleType("worker.backend")
    models_mod = types.ModuleType("worker.models")
    worker_mod = types.ModuleType("worker")

    class Backend:
        def setup(self):
            pass

        def run(self, policy_name, policy):
            return []

    backend_mod.Backend = Backend
    models_mod.Metadata = StubMetadata
    models_mod.Policy = StubPolicy

    sys.modules["worker"] = worker_mod
    sys.modules["worker.backend"] = backend_mod
    sys.modules["worker.models"] = models_mod


_install_stubs()
