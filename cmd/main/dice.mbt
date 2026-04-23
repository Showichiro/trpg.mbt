///|
fn parse_dice_expr(expr : String) -> Array[DiceTerm] raise TrpgFailure {
  let cleaned = expr.replace_all(old=" ", new="")
  if cleaned.is_empty() {
    fail(TrpgError::Usage("empty dice expression", Some("use 2d6+3")))
  }
  let normalized = cleaned.replace_all(old="-", new="+-")
  let pieces = normalized.split("+").map(piece => piece.to_string()).collect()
  let terms : Array[DiceTerm] = []
  for piece in pieces {
    if piece.is_empty() {
      continue
    }
    let (sign, body) = if piece.has_prefix("-") {
      (-1, piece[1:].to_string())
    } else {
      (1, piece)
    }
    if body.is_empty() {
      fail(TrpgError::Usage("invalid dice term: \{piece}", Some("use 2d6+3")))
    }
    match body.split_once("d") {
      Some((count_text, sides_text)) => {
        let count = parse_int_arg(count_text.to_string(), "dice count")
        let sides = parse_int_arg(sides_text.to_string(), "dice sides")
        if count <= 0 || sides <= 0 {
          fail(
            TrpgError::Usage(
              "invalid dice term: \{piece}",
              Some("dice count and sides must be positive"),
            ),
          )
        }
        terms.push({ sign, count, sides, value: 0, is_dice: true })
      }
      None => {
        let value = parse_int_arg(body, "modifier")
        terms.push({ sign, count: 0, sides: 0, value, is_dice: false })
      }
    }
  }
  if terms.length() == 0 {
    fail(
      TrpgError::Usage("invalid dice expression: \{expr}", Some("use 2d6+3")),
    )
  } else {
    terms
  }
}

///|
fn seeded_rng() -> @random.Rand {
  let rng = @random.Rand::new()
  let skip = (@env.now() % 997UL).reinterpret_as_int64().to_int()
  for _ in 0..<skip {
    rng.int(limit=1000000) |> ignore
  }
  rng
}

///|
fn eval_dice(expr : String) -> RollEval raise TrpgFailure {
  let terms = parse_dice_expr(expr)
  let rng = seeded_rng()
  let rolls : Array[Int] = []
  let parts : Array[String] = []
  let mut total = 0
  let mut mod = 0
  for term in terms {
    if term.is_dice {
      for _ in 0..<term.count {
        let roll = rng.int(limit=term.sides) + 1
        rolls.push(roll)
        total += term.sign * roll
        let text = roll.to_string()
        if parts.length() == 0 {
          parts.push(if term.sign < 0 { "-" + text } else { text })
        } else {
          parts.push(if term.sign < 0 { "-" + text } else { "+" + text })
        }
      }
    } else {
      let signed = term.sign * term.value
      mod += signed
      total += signed
      let text = term.value.to_string()
      if parts.length() == 0 {
        parts.push(if signed < 0 { "-" + text } else { text })
      } else {
        parts.push(if signed < 0 { "-" + text } else { "+" + text })
      }
    }
  }
  { total, rolls, mod, breakdown: parts.join("") }
}

///|
fn roll_outcome(total : Int, target : Int?) -> String {
  match target {
    Some(value) => if total >= value { "HIT" } else { "MISS" }
    None => "NONE"
  }
}
