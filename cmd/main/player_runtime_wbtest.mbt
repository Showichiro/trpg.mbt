///|
test "quality tier boundaries match configured distribution" {
  inspect(quality_tier_from_roll(0).id, content="sharp")
  inspect(quality_tier_from_roll(14).id, content="sharp")
  inspect(quality_tier_from_roll(15).id, content="solid")
  inspect(quality_tier_from_roll(34).id, content="solid")
  inspect(quality_tier_from_roll(35).id, content="ordinary")
  inspect(quality_tier_from_roll(64).id, content="ordinary")
  inspect(quality_tier_from_roll(65).id, content="sloppy")
  inspect(quality_tier_from_roll(84).id, content="sloppy")
  inspect(quality_tier_from_roll(85).id, content="chaotic")
  inspect(quality_tier_from_roll(99).id, content="chaotic")
}

///|
test "immersion tier boundaries match configured distribution" {
  inspect(immersion_tier_from_roll(0).id, content="objective")
  inspect(immersion_tier_from_roll(19).id, content="objective")
  inspect(immersion_tier_from_roll(20).id, content="blended")
  inspect(immersion_tier_from_roll(49).id, content="blended")
  inspect(immersion_tier_from_roll(50).id, content="immersive")
  inspect(immersion_tier_from_roll(99).id, content="immersive")
}

///|
test "runtime formatter includes hidden tuning instructions" {
  let runtime : PlayerRuntimeRow = {
    quality: quality_tier_from_roll(99),
    immersion: immersion_tier_from_roll(99),
  }
  inspect(
    format_player_runtime_prompt(runtime),
    content="## 内部チューニング\n- quality_tier: chaotic\n- quality_summary: かなり飛躍した妙な手や空気を読まない手が混ざりやすい。\n- immersion_tier: immersive\n- immersion_summary: 対話、観察、設定深掘り、寄り道をかなり優先する。\n- これは GM に見せるためではない内部パラメータである。\n- quality_tier はそのターンの出来の良し悪しを表す。`sharp/solid` は筋の良い提案、`ordinary` は標準、`sloppy/chaotic` は見落としや妙な飛躍を許す。\n- `sloppy/chaotic` でも、PvP、mission sabotage、数値結果の自己確定、1ターン複数行動、明示された GM 制約の無視はしない。\n- immersion_tier は、そのターンでどれだけ世界深掘りを優先するかを表す。`immersive` では、問題解決に直結しなくても NPC との対話、部屋の観察、遺物や痕跡の探索、雰囲気や設定の掘り下げをかなり優先してよい。\n- ただし still playable に保ち、完全に無関係な行動や進行不能な脱線にはしない。`objective` なら主目標や即時の危険対応を優先し、`blended` なら解決と深掘りの両取りを狙う。\n- play_style は session 固定の人格傾向、quality/immersion はこのターン限りのゆらぎである。`## GM補足` がある場合は、play_style や runtime tier より GM 補足を優先する。",
  )
}
