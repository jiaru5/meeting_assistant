from __future__ import annotations

import os
from pathlib import Path
from typing import Mapping


DEFAULT_WORKSPACE = Path("~/Movies/MeetingAssistant").expanduser()


def default_workspace(env: Mapping[str, str] | None = None) -> Path:
    env_map = os.environ if env is None else env
    configured = env_map.get("MEETING_ASSISTANT_WORKSPACE", "").strip()
    return Path(configured).expanduser() if configured else DEFAULT_WORKSPACE
