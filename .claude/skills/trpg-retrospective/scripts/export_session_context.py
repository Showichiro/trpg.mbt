#!/usr/bin/env python3
import argparse
import json
import os
import sqlite3
from datetime import datetime
from pathlib import Path
from typing import Any


def trpg_home() -> Path:
    value = os.environ.get("TRPG_HOME")
    if value:
        return Path(value).expanduser()
    home = os.environ.get("HOME")
    if not home:
        raise SystemExit("TRPG_HOME も HOME も未設定です")
    return Path(home).expanduser() / ".trpg"


def parse_json_or_none(text: str | None) -> Any:
    if text is None or text == "":
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return None


def load_scenario(path: Path) -> Any:
    if not path.exists():
        return None
    return json.loads(path.read_text(encoding="utf-8"))


def choose_session(conn: sqlite3.Connection, session_id: int | None) -> tuple[sqlite3.Row, str]:
    if session_id is not None:
        row = conn.execute(
            """
            SELECT id, scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome
            FROM sessions
            WHERE id = ?
            """,
            (session_id,),
        ).fetchone()
        if row is None:
            raise SystemExit(f"session_id={session_id} は見つかりません")
        return row, "explicit"

    row = conn.execute(
        """
        SELECT id, scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome
        FROM sessions
        WHERE is_active = 1
        ORDER BY id DESC
        LIMIT 1
        """
    ).fetchone()
    if row is not None:
        return row, "active"

    row = conn.execute(
        """
        SELECT id, scenario_id, started_at_ms, current_scene, is_active, ended_at_ms, outcome
        FROM sessions
        ORDER BY id DESC
        LIMIT 1
        """
    ).fetchone()
    if row is None:
        raise SystemExit("active session も latest session もありません")
    return row, "latest"


def build_report_path(reports_dir: Path, scenario_id: str, session_id: int) -> Path:
    reports_dir.mkdir(parents=True, exist_ok=True)
    base = reports_dir / f"{scenario_id}-{session_id}.md"
    if not base.exists():
        return base
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    return reports_dir / f"{scenario_id}-{session_id}-{stamp}.md"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Export TRPG session context for retrospective writing"
    )
    parser.add_argument("--session-id", type=int, default=None)
    parser.add_argument("--event-limit", type=int, default=5000)
    args = parser.parse_args()

    home = trpg_home()
    db_path = home / "trpg.db"
    if not db_path.exists():
        raise SystemExit(f"DB が見つかりません: {db_path}")

    conn = sqlite3.connect(str(db_path))
    conn.row_factory = sqlite3.Row

    session, mode = choose_session(conn, args.session_id)
    session_id = int(session["id"])
    scenario_id = str(session["scenario_id"])

    characters = conn.execute(
        """
        SELECT c.id, c.name, c.kind, c.sheet_json, s.hp_cur, s.hp_max, s.conditions_json
        FROM characters c
        JOIN statuses s ON s.character_id = c.id
        WHERE c.session_id = ?
        ORDER BY c.id ASC
        """,
        (session_id,),
    ).fetchall()

    events = conn.execute(
        """
        SELECT id, session_id, kind, actor, subject, text, data_json, created_at_ms
        FROM events
        WHERE session_id = ?
        ORDER BY id ASC
        LIMIT ?
        """,
        (session_id, args.event_limit),
    ).fetchall()

    scenario_path = home / "scenarios" / f"{scenario_id}.json"
    reports_dir = home / "reports"
    output = {
        "selection_mode": mode,
        "trpg_home": str(home),
        "db_path": str(db_path),
        "scenario_path": str(scenario_path),
        "report_path_suggestion": str(build_report_path(reports_dir, scenario_id, session_id)),
        "generated_at": datetime.now().isoformat(timespec="seconds"),
        "session": {
            "id": session_id,
            "scenario_id": scenario_id,
            "started_at_ms": session["started_at_ms"],
            "current_scene": session["current_scene"],
            "is_active": bool(session["is_active"]),
            "ended_at_ms": session["ended_at_ms"],
            "outcome": session["outcome"],
        },
        "scenario": load_scenario(scenario_path),
        "characters": [
            {
                "id": row["id"],
                "name": row["name"],
                "kind": row["kind"],
                "hp_cur": row["hp_cur"],
                "hp_max": row["hp_max"],
                "sheet": parse_json_or_none(row["sheet_json"]),
                "conditions": parse_json_or_none(row["conditions_json"]),
            }
            for row in characters
        ],
        "events": [
            {
                "id": row["id"],
                "session_id": row["session_id"],
                "kind": row["kind"],
                "actor": row["actor"],
                "subject": row["subject"],
                "text": row["text"],
                "data": parse_json_or_none(row["data_json"]),
                "created_at_ms": row["created_at_ms"],
            }
            for row in events
        ],
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
