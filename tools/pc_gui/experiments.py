from __future__ import annotations

import json
import os
import uuid
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


@dataclass(frozen=True, slots=True)
class ExperimentTemplate:
    id: str
    name: str
    athlete: str = ""
    topic: str = ""
    sample_rate_hz: int = 100
    notes: str = ""
    tags: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        if not self.id:
            raise ValueError("experiment id is required")
        if not self.name.strip():
            raise ValueError("experiment name is required")
        if self.sample_rate_hz not in {50, 100, 200}:
            raise ValueError("sample_rate_hz must be 50, 100, or 200")

    @classmethod
    def new(
        cls,
        *,
        name: str,
        athlete: str = "",
        topic: str = "",
        sample_rate_hz: int = 100,
        notes: str = "",
        tags: tuple[str, ...] = (),
    ) -> "ExperimentTemplate":
        return cls(
            id=str(uuid.uuid4()),
            name=name.strip(),
            athlete=athlete.strip(),
            topic=topic.strip(),
            sample_rate_hz=sample_rate_hz,
            notes=notes.strip(),
            tags=tuple(tag.strip() for tag in tags if tag.strip()),
        )

    @classmethod
    def from_json(cls, value: dict[str, Any]) -> "ExperimentTemplate":
        raw_tags = value.get("tags", [])
        tags = tuple(str(item) for item in raw_tags) if isinstance(raw_tags, list) else ()
        return cls(
            id=str(value["id"]),
            name=str(value["name"]),
            athlete=str(value.get("athlete", "")),
            topic=str(value.get("topic", "")),
            sample_rate_hz=int(value.get("sample_rate_hz", 100)),
            notes=str(value.get("notes", "")),
            tags=tags,
        )

    def to_json(self) -> dict[str, Any]:
        value = asdict(self)
        value["tags"] = list(self.tags)
        return value


class ExperimentStore:
    """Small crash-safe JSON store for reusable recording presets."""

    def __init__(self, path: Path | str) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    @classmethod
    def default(cls) -> "ExperimentStore":
        root = Path.home() / "Documents" / "WheelAthlete"
        return cls(root / "experiments.json")

    def load(self) -> list[ExperimentTemplate]:
        try:
            raw = json.loads(self.path.read_text(encoding="utf-8"))
        except FileNotFoundError:
            return []
        except (OSError, json.JSONDecodeError) as exc:
            raise RuntimeError(f"failed to load experiments from {self.path}: {exc}") from exc
        if not isinstance(raw, list):
            raise RuntimeError(f"experiment file must contain a JSON array: {self.path}")
        result: list[ExperimentTemplate] = []
        for item in raw:
            if not isinstance(item, dict):
                continue
            try:
                result.append(ExperimentTemplate.from_json(item))
            except (KeyError, TypeError, ValueError):
                continue
        return result

    def save_all(self, values: list[ExperimentTemplate]) -> None:
        payload = [item.to_json() for item in values]
        temp = self.path.with_suffix(self.path.suffix + ".tmp")
        with temp.open("w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2, ensure_ascii=False)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temp, self.path)

    def upsert(self, value: ExperimentTemplate) -> list[ExperimentTemplate]:
        items = self.load()
        updated = False
        for index, item in enumerate(items):
            if item.id == value.id:
                items[index] = value
                updated = True
                break
        if not updated:
            items.append(value)
        self.save_all(items)
        return items

    def delete(self, template_id: str) -> list[ExperimentTemplate]:
        items = [item for item in self.load() if item.id != template_id]
        self.save_all(items)
        return items
