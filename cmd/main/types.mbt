///|
struct RunResult {
  stdout : String
  stderr : String
  exit_code : Int
}

///|
struct GlobalArgs {
  args : Array[String]
  human : Bool
  quiet : Bool
  describe : Bool
}

///|
struct CliOutput {
  json : Json
  human : String
  stderr : String
}

///|
struct SessionRow {
  id : Int
  scenario_id : String
  started_at_ms : Int64
  current_scene : String
}

///|
struct CharacterRow {
  id : Int
  name : String
  kind : String
  sheet_json : String
  hp_cur : Int
  hp_max : Int
  conditions_json : String
}

///|
struct LogRow {
  id : Int
  actor : String
  text : String
  created_at_ms : Int64
}

///|
struct RollRow {
  id : Int
  expr : String
  total : Int
  target : Int?
  outcome : String
  rolled_by : String?
  context : String?
  created_at_ms : Int64
}

///|
struct HistoryEntry {
  created_at_ms : Int64
  sort_order : Int
  text : String
}

///|
struct ModifierPreviewRow {
  name : String
  amount : Int
  uses : Int?
  duration : String?
  on_trigger : String?
  note : String
}

///|
struct RollPreview {
  ability : String
  base_stat : Int
  auto_total : Int
  modifiers : Array[ModifierPreviewRow]
  manual_traits : Array[String]
  inventory : Array[String]
}

///|
struct RollEval {
  total : Int
  rolls : Array[Int]
  mod : Int
  breakdown : String
}

///|
struct DiceTerm {
  sign : Int
  count : Int
  sides : Int
  value : Int
  is_dice : Bool
}

///|
enum TrpgError {
  Usage(String, String?)
  General(String, String?)
  NotFound(String, String?)
  Permission(String, String?)
  Conflict(String, String?)
} derive(Debug)

///|
suberror TrpgFailure {
  TrpgFailure(TrpgError)
}
