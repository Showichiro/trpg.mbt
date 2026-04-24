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
  help : Bool
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
  is_active : Bool
  ended_at_ms : Int64?
  outcome : String?
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
struct EventRow {
  id : Int
  session_id : Int
  kind : String
  actor : String?
  subject : String?
  text : String
  data_json : String
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
  kind : String
  name : String
  amount : Int
  tags : Array[String]
  source : String?
  uses : Int?
  duration : String?
  on_trigger : String?
  note : String
}

///|
struct SkippedModifierRow {
  kind : String
  name : String
  reason : String
  effect_stat : String
  requested_stat : String
  effect_tags : Array[String]
  requested_tags : Array[String]
  effect_trigger : String
}

///|
struct ModifierResolution {
  matched : Array[ModifierPreviewRow]
  skipped : Array[SkippedModifierRow]
}

///|
struct RollPreview {
  ability : String
  base_stat : Int
  auto_total : Int
  modifiers : Array[ModifierPreviewRow]
  skipped_modifiers : Array[SkippedModifierRow]
  inventory : Array[String]
}

///|
struct SceneModifierRow {
  name : String
  target_delta : Int
  stat : String?
  tags : Array[String]
  note : String
  source : String?
  scope : String
}

///|
struct PlayStyleRow {
  id : String
  display_name : String
  summary : String
  impulse : String
  risk_tolerance : String
  cooperation_mode : String
  idea_bias : String
}

///|
struct ActorRollRow {
  actor : String
  ability : String
  base_stat : Int
  auto_modifier_total : Int
  bonus : Int
  total_modifier : Int
  target : Int?
  expr : String
  total : Int
  rolls : Array[Int]
  outcome : String
  margin : Int?
  special : String
  modifiers : Array[ModifierPreviewRow]
  skipped_modifiers : Array[SkippedModifierRow]
  consumed_statuses : Array[String]
  scene_modifiers : Array[SceneModifierRow]
  scene_target_modifier : Int
  scene_warning : String?
}

///|
struct GrantedStatusRow {
  target : String
  name : String
  ability : String
  amount : Int
  tags : Array[String]
  source : String?
  uses : Int
  duration : String?
  on_trigger : String
}

///|
struct GoalStatusRow {
  id : String
  outcome : String
  satisfied : Bool
  summary : String
}

///|
struct ScenarioInstallRow {
  id : String
  title : String
  summary : String
  version : String?
  path : String
  origin : String
  source_url : String?
  installed_at_ms : Int64?
}

///|
struct ScenarioSourceRow {
  scenario_id : String
  source_kind : String
  source_label : String
  source_text : String
  scenario : Json
  source_url : String?
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
