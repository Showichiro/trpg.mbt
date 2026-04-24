///|
test "grant status formatter includes uses duration and trigger" {
  let granted : GrantedStatusRow = {
    target: "alice",
    name: "所作援護",
    ability: "tech",
    amount: 1,
    tags: ["ritual", "seal"],
    source: Some("orion"),
    uses: 2,
    duration: Some("scene"),
    on_trigger: "consume",
  }
  inspect(
    format_granted_status(granted),
    content="alice <= 所作援護 (tech +1 / tags=ritual,seal / uses=2 / on_trigger=consume / duration=scene / source=orion)",
  )
  inspect(
    grant_status_json(granted).stringify(),
    content="{\"target\":\"alice\",\"name\":\"所作援護\",\"ability\":\"tech\",\"amount\":1,\"tags\":[\"ritual\",\"seal\"],\"uses\":2,\"on_trigger\":\"consume\",\"source\":\"orion\",\"duration\":\"scene\"}",
  )
}

///|
test "next-roll target delta accepts target shorthand" {
  inspect(parse_next_roll_target_delta("target:-2"), content="-2")
}

///|
test "grant on-trigger parser accepts consume and persist" {
  inspect(normalize_grant_on_trigger("consume"), content="consume")
  inspect(normalize_grant_on_trigger("persist"), content="persist")
}

///|
test "actor-aware roll requires resolved target unless preview" {
  let err = try? ensure_resolved_actor_roll_target(None, false)
  inspect(
    match err {
      Ok(_) => false
      Err(_) => true
    },
    content="true",
  )
  let ok = try? ensure_resolved_actor_roll_target(None, true)
  inspect(
    match ok {
      Ok(_) => true
      Err(_) => false
    },
    content="true",
  )
}
