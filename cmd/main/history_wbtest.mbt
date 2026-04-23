///|
test "history from roll includes actor target outcome and context" {
  let rendered = format_history_for_prompt([
    history_from_roll({
      id: 7,
      expr: "2d6+3",
      total: 10,
      target: Some(9),
      outcome: "HIT",
      rolled_by: Some("alice"),
      context: Some("扉の解錠"),
      created_at_ms: 100,
    }),
  ])
  inspect(
    rendered,
    content="- 判定 alice: 2d6+3 = 10 / target=9 / HIT / 扉の解錠",
  )
}

///|
test "history formatting falls back when optional roll fields are absent" {
  let rendered = format_history_for_prompt([
    history_from_roll({
      id: 8,
      expr: "2d6",
      total: 5,
      target: None,
      outcome: "MISS",
      rolled_by: None,
      context: None,
      created_at_ms: 200,
    }),
  ])
  inspect(rendered, content="- 判定 gm: 2d6 = 5 / MISS")
}
