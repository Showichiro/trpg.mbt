///|
fn history_from_log(row : LogRow) -> HistoryEntry {
  {
    created_at_ms: row.created_at_ms,
    sort_order: row.id,
    text: "\{row.actor}: \{row.text}",
  }
}

///|
fn history_from_event(row : EventRow) -> HistoryEntry {
  ignore(row.session_id)
  ignore(row.subject)
  { created_at_ms: row.created_at_ms, sort_order: row.id, text: row.text }
}

///|
fn history_from_roll(row : RollRow) -> HistoryEntry {
  let actor = row.rolled_by.unwrap_or("gm")
  let target_text = match row.target {
    Some(target) => " / target=\{target}"
    None => ""
  }
  let context_text = match row.context {
    Some(text) if !text.is_empty() => " / \{text}"
    _ => ""
  }
  {
    created_at_ms: row.created_at_ms,
    sort_order: 1000000 + row.id,
    text: "判定 \{actor}: \{row.expr} = \{row.total}\{target_text} / \{row.outcome}\{context_text}",
  }
}

///|
fn merge_history_entries(
  left : Array[HistoryEntry],
  right : Array[HistoryEntry],
) -> Array[HistoryEntry] {
  let merged : Array[HistoryEntry] = []
  let mut i = 0
  let mut j = 0
  while i < left.length() && j < right.length() {
    let use_left = if left[i].created_at_ms < right[j].created_at_ms {
      true
    } else if left[i].created_at_ms > right[j].created_at_ms {
      false
    } else {
      left[i].sort_order <= right[j].sort_order
    }
    if use_left {
      merged.push(left[i])
      i += 1
    } else {
      merged.push(right[j])
      j += 1
    }
  }
  while i < left.length() {
    merged.push(left[i])
    i += 1
  }
  while j < right.length() {
    merged.push(right[j])
    j += 1
  }
  merged
}

///|
fn take_last_history(
  entries : Array[HistoryEntry],
  limit : Int,
) -> Array[HistoryEntry] {
  if entries.length() <= limit {
    entries
  } else {
    let start = entries.length() - limit
    let out : Array[HistoryEntry] = []
    for i in start..<entries.length() {
      out.push(entries[i])
    }
    out
  }
}

///|
fn recent_history(
  db : @sqlite.Database,
  session_id : Int,
  limit : Int,
) -> Array[HistoryEntry] raise TrpgFailure {
  let events = recent_events(db, session_id, limit)
  if events.length() > 0 {
    events.map(history_from_event)
  } else {
    let logs = recent_logs(db, session_id, limit).map(history_from_log)
    let rolls = recent_rolls(db, session_id, limit).map(history_from_roll)
    let merged = merge_history_entries(logs, rolls)
    take_last_history(merged, limit)
  }
}

///|
fn format_history_for_prompt(entries : Array[HistoryEntry]) -> String {
  if entries.length() == 0 {
    "(なし)"
  } else {
    entries.map(entry => "- \{entry.text}").join("\n")
  }
}
