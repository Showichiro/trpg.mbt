///|
test "parse dice expression keeps dice and modifier terms" {
  let terms = parse_dice_expr("2d6+3-1")
  inspect(terms.length(), content="3")
  inspect(terms[0].sign, content="1")
  inspect(terms[0].count, content="2")
  inspect(terms[0].sides, content="6")
  inspect(terms[1].value, content="3")
  inspect(terms[2].sign, content="-1")
  inspect(terms[2].value, content="1")
}

///|
test "parse dice expression rejects non-positive dice" {
  let message = try {
    parse_dice_expr("0d6") |> ignore
    "ok"
  } catch {
    TrpgFailure(Usage(text, _)) => text
    TrpgFailure(_) => "wrong error"
  }
  inspect(message, content="invalid dice term: 0d6")
}

///|
test "roll outcome respects target" {
  inspect(roll_outcome(10, Some(10)), content="HIT")
  inspect(roll_outcome(9, Some(10)), content="MISS")
  inspect(roll_outcome(9, None), content="NONE")
}
