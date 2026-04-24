///|
test "mixed-interest private contract asks for public and private sections" {
  inspect(
    format_player_response_contract("mixed_interest", "private"),
    content="このシナリオは半協力で、PC 同士の利害が一致しない場面がある。\n返答は必ず次の 2 節で分ける。\n## 公開行動\n- 卓上で見える発言、動作、提案だけを書く。\n## 非公開意図\n- 本当の狙い、温存したい交渉材料、誰に何を隠したいかを書く。\nGM は mixed_interest では公開行動だけを卓上に返し、非公開意図は他プレイヤーへ流さない。",
  )
}

///|
test "mixed-interest public contract hides private intent" {
  inspect(
    format_player_response_contract("mixed_interest", "public"),
    content="このシナリオは半協力で、PC 同士の利害が一致しない場面がある。\n返答は公開行動だけに絞る。卓上で見える発言、動作、提案だけを書き、秘密の狙いや本音は書かない。",
  )
}
