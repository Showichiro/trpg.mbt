///|
fn quality_tier_from_roll(roll : Int) -> QualityTierRow {
  if roll < 15 {
    {
      id: "sharp",
      summary: "文脈理解が高く、筋の良い一手を出しやすい。",
    }
  } else if roll < 35 {
    { id: "solid", summary: "安定して良い手を出しやすい。" }
  } else if roll < 65 {
    { id: "ordinary", summary: "無難で標準的な手を選びやすい。" }
  } else if roll < 85 {
    {
      id: "sloppy",
      summary: "見落としや短絡を含む雑な手が混ざりやすい。",
    }
  } else {
    {
      id: "chaotic",
      summary: "かなり飛躍した妙な手や空気を読まない手が混ざりやすい。",
    }
  }
}

///|
fn immersion_tier_from_roll(roll : Int) -> ImmersionTierRow {
  if roll < 20 {
    {
      id: "objective",
      summary: "主目標や即時の障害解決を優先する。",
    }
  } else if roll < 50 {
    { id: "blended", summary: "解決と世界深掘りの両方を狙う。" }
  } else {
    {
      id: "immersive",
      summary: "対話、観察、設定深掘り、寄り道をかなり優先する。",
    }
  }
}

///|
fn random_player_runtime() -> PlayerRuntimeRow {
  let rng = seeded_rng()
  {
    quality: quality_tier_from_roll(rng.int(limit=100)),
    immersion: immersion_tier_from_roll(rng.int(limit=100)),
  }
}

///|
fn format_player_runtime_prompt(runtime : PlayerRuntimeRow) -> String {
  "## 内部チューニング\n" +
  "- quality_tier: \{runtime.quality.id}\n" +
  "- quality_summary: \{runtime.quality.summary}\n" +
  "- immersion_tier: \{runtime.immersion.id}\n" +
  "- immersion_summary: \{runtime.immersion.summary}\n" +
  "- これは GM に見せるためではない内部パラメータである。\n" +
  "- quality_tier はそのターンの出来の良し悪しを表す。`sharp/solid` は筋の良い提案、`ordinary` は標準、`sloppy/chaotic` は見落としや妙な飛躍を許す。\n" +
  "- `sloppy/chaotic` でも、PvP、mission sabotage、数値結果の自己確定、1ターン複数行動、明示された GM 制約の無視はしない。\n" +
  "- immersion_tier は、そのターンでどれだけ世界深掘りを優先するかを表す。`immersive` では、問題解決に直結しなくても NPC との対話、部屋の観察、遺物や痕跡の探索、雰囲気や設定の掘り下げをかなり優先してよい。\n" +
  "- ただし still playable に保ち、完全に無関係な行動や進行不能な脱線にはしない。`objective` なら主目標や即時の危険対応を優先し、`blended` なら解決と深掘りの両取りを狙う。\n" +
  "- play_style は session 固定の人格傾向、quality/immersion はこのターン限りのゆらぎである。`## GM補足` がある場合は、play_style や runtime tier より GM 補足を優先する。"
}
