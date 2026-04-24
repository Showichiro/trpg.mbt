///|
fn play_style_catalog() -> Array[PlayStyleRow] {
  [
    {
      id: "wildcard",
      display_name: "ワイルドカード",
      summary: "思いついた搦め手や奇抜な突破口を出しやすい。",
      impulse: "unexpected",
      risk_tolerance: "medium-high",
      cooperation_mode: "cooperative",
      idea_bias: "奇策と即興を優先する",
    },
    {
      id: "schemer",
      display_name: "策士",
      summary: "準備、段取り、仕込みから勝ち筋を作る。",
      impulse: "deliberate",
      risk_tolerance: "medium",
      cooperation_mode: "cooperative",
      idea_bias: "prep と self-grant を好む",
    },
    {
      id: "cautious",
      display_name: "慎重派",
      summary: "確認、撤退、低リスクの進め方を優先する。",
      impulse: "measured",
      risk_tolerance: "low",
      cooperation_mode: "cooperative",
      idea_bias: "確認や安全策を選びやすい",
    },
    {
      id: "supportive",
      display_name: "援護役",
      summary: "味方への援護、情報整理、段取りを優先する。",
      impulse: "team-first",
      risk_tolerance: "medium",
      cooperation_mode: "supportive",
      idea_bias: "援護、橋渡し、役割分担を選びやすい",
    },
    {
      id: "dramatic",
      display_name: "ドラマ志向",
      summary: "見せ場や緊張感のある行動を好むが協力は崩さない。",
      impulse: "cinematic",
      risk_tolerance: "medium-high",
      cooperation_mode: "cooperative",
      idea_bias: "印象的で絵になる一手を好む",
    },
    {
      id: "contrarian",
      display_name: "ひねくれ案派",
      summary: "定石外しや別角度の提案を出しやすい。",
      impulse: "contrarian",
      risk_tolerance: "medium",
      cooperation_mode: "cooperative",
      idea_bias: "定石を外した別解を探しやすい",
    },
  ]
}

///|
fn fallback_play_style(style_id : String) -> PlayStyleRow {
  {
    id: style_id,
    display_name: style_id,
    summary: "この PC 固有のスタイルを保ちつつ協力的に動く。",
    impulse: "custom",
    risk_tolerance: "medium",
    cooperation_mode: "cooperative",
    idea_bias: "既存の文脈に沿って提案する",
  }
}

///|
fn find_catalog_play_style(style_id : String) -> PlayStyleRow? {
  let mut found : PlayStyleRow? = None
  for style in play_style_catalog() {
    match found {
      Some(_) => ()
      None => if style.id == style_id { found = Some(style) }
    }
  }
  found
}

///|
fn require_catalog_play_style(
  style_id : String,
) -> PlayStyleRow raise TrpgFailure {
  match find_catalog_play_style(style_id) {
    Some(style) => style
    None =>
      fail(
        TrpgError::Usage(
          "unknown play_style: \{style_id}",
          Some(
            "supported styles: " +
            play_style_catalog().map(fn(style) { style.id }).join(", "),
          ),
        ),
      )
  }
}

///|
fn resolve_play_style(style_id : String) -> PlayStyleRow {
  match find_catalog_play_style(style_id) {
    Some(style) => style
    None => fallback_play_style(style_id)
  }
}

///|
fn random_play_style() -> PlayStyleRow {
  let styles = play_style_catalog()
  let rng = seeded_rng()
  styles[rng.int(limit=styles.length())]
}

///|
fn rerolled_play_style(current : PlayStyleRow?) -> PlayStyleRow {
  let styles = play_style_catalog()
  if styles.length() <= 1 {
    random_play_style()
  } else {
    let rng = seeded_rng()
    let current_id = match current {
      Some(style) => style.id
      None => ""
    }
    let mut picked = styles[rng.int(limit=styles.length())]
    while picked.id == current_id {
      picked = styles[rng.int(limit=styles.length())]
    }
    picked
  }
}

///|
fn play_style_assignment_json(style : PlayStyleRow) -> Json {
  Json::object({ "id": Json::string(style.id) })
}

///|
fn play_style_json(style : PlayStyleRow) -> Json {
  Json::object({
    "id": Json::string(style.id),
    "display_name": Json::string(style.display_name),
    "summary": Json::string(style.summary),
    "impulse": Json::string(style.impulse),
    "risk_tolerance": Json::string(style.risk_tolerance),
    "cooperation_mode": Json::string(style.cooperation_mode),
    "idea_bias": Json::string(style.idea_bias),
  })
}

///|
fn play_style_from_sheet_json(
  source : String,
) -> PlayStyleRow? raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  match sheet.get("play_style") {
    Some(Object(object)) =>
      match object.get("id") {
        Some(String(style_id)) if !style_id.is_empty() =>
          Some(resolve_play_style(style_id))
        _ => None
      }
    _ => None
  }
}

///|
fn set_play_style_json(
  source : String,
  style : PlayStyleRow,
) -> String raise TrpgFailure {
  let sheet = parse_sheet_object(source, "sheet_json")
  sheet["play_style"] = play_style_assignment_json(style)
  Json::object(sheet).stringify()
}

///|
fn format_play_style_human(style : PlayStyleRow) -> String {
  "\{style.display_name} [\{style.id}] - \{style.summary}"
}

///|
fn format_play_style_prompt(style : PlayStyleRow, brief : Bool) -> String {
  if brief {
    format_play_style_human(style) +
    "\nこの傾向は行動提案の方向性だけに効く。協力前提とルール順守は崩さない。"
  } else {
    "- style_id: \{style.id}\n" +
    "- 表示名: \{style.display_name}\n" +
    "- 傾向: \{style.summary}\n" +
    "- 衝動: \{style.impulse}\n" +
    "- リスク許容: \{style.risk_tolerance}\n" +
    "- 協力モード: \{style.cooperation_mode}\n" +
    "- 発想バイアス: \{style.idea_bias}\n" +
    "- これは行動提案の方向性であり、数値補正ではない。協力前提とルール順守は崩さない。"
  }
}

///|
fn ensure_character_play_style(
  db : @sqlite.Database,
  row : CharacterRow,
) -> (CharacterRow, PlayStyleRow) raise TrpgFailure {
  match play_style_from_sheet_json(row.sheet_json) {
    Some(style) => (row, style)
    None => {
      let style = random_play_style()
      let next_sheet = set_play_style_json(row.sheet_json, style)
      update_character_sheet(db, row.id, next_sheet)
      (
        {
          id: row.id,
          name: row.name,
          kind: row.kind,
          sheet_json: next_sheet,
          hp_cur: row.hp_cur,
          hp_max: row.hp_max,
          conditions_json: row.conditions_json,
        },
        style,
      )
    }
  }
}

///|
fn assign_character_play_style(
  db : @sqlite.Database,
  row : CharacterRow,
  style : PlayStyleRow,
) -> (CharacterRow, PlayStyleRow) raise TrpgFailure {
  let next_sheet = set_play_style_json(row.sheet_json, style)
  update_character_sheet(db, row.id, next_sheet)
  (
    {
      id: row.id,
      name: row.name,
      kind: row.kind,
      sheet_json: next_sheet,
      hp_cur: row.hp_cur,
      hp_max: row.hp_max,
      conditions_json: row.conditions_json,
    },
    style,
  )
}
