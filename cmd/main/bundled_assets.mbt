///|
fn bundled_scenario_ids() -> Array[String] {
  ["forgotten_library", "festival_bathhouse_fire", "midnight_auction"]
}

///|
fn bundled_scenario_text(id : String) -> String? {
  match id {
    "forgotten_library" =>
      Some(
        "{\"id\":\"forgotten_library\",\"title\":\"忘れられた図書館の鍵\",\"summary\":\"三百年前に封じられた魔導書の鍵を、朽ちかけた図書館から取り戻す。\",\"party_setup\":{\"solo_friendly\":true,\"recommended_party_size\":{\"min\":1,\"max\":2},\"default_participants\":{\"1\":[\"alice\"],\"2\":[\"alice\",\"orion\"]},\"sample_pcs\":[\"alice\",\"orion\"]},\"opening_scene\":\"entrance\",\"goals\":[{\"id\":\"recover-silver-key\",\"kind\":\"inventory_ever_contained\",\"actor\":\"any_pc\",\"item_id\":\"銀の鍵\",\"outcome\":\"success\"},{\"id\":\"seal-stabilized\",\"kind\":\"scene_flag\",\"scene\":\"seal\",\"flag\":\"sealed\",\"equals\":\"true\",\"outcome\":\"success\"}],\"scenes\":{\"entrance\":{\"description\":\"苔むした入口。床には古い魔法陣の残滓があり、重い扉の奥から湿った紙の匂いが漂う。\",\"difficulty\":{\"stat\":\"body\",\"target\":9,\"tags\":[\"forced-entry\",\"ruins\"]},\"transitions\":[{\"to\":\"librarian\",\"label\":\"蔵書の間へ進む\",\"requires\":[]}]},\"librarian\":{\"description\":\"蔵書の間には司書の亡霊が佇む。彼女は失われた貸出記録を守り、来訪者の意図を見定めようとする。\",\"difficulty\":{\"stat\":\"mind\",\"target\":9,\"tags\":[\"parley\",\"ancient-text\"]},\"transitions\":[{\"to\":\"seal\",\"label\":\"地下書庫へ向かう\",\"requires\":[]}]},\"seal\":{\"description\":\"地下書庫の石棺には複雑な魔法紋様が刻まれている。鍵は封印の中心で淡く脈打っている。\",\"difficulty\":{\"stat\":\"tech\",\"target\":11,\"tags\":[\"ritual\",\"seal\"]},\"transitions\":[]}},\"npcs\":[{\"name\":\"司書の亡霊\",\"kind\":\"npc\",\"sheet\":{\"name\":\"司書の亡霊\",\"class\":\"亡霊\",\"stats\":{\"body\":0,\"tech\":1,\"mind\":2},\"hp_max\":8,\"traits\":[{\"id\":\"ancient-catalog\",\"name\":\"古い目録知識\",\"desc\":\"図書館の歴史や貸出記録を辿る心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"ancient-text\",\"parley\"],\"trigger\":\"roll\"}]}],\"inventory\":[{\"id\":\"銀の鍵\",\"name\":\"銀の鍵\",\"desc\":\"封印石棺の中心にはまる古い鍵\",\"effects\":[]}]}}]}\n",
      )
    "festival_bathhouse_fire" =>
      Some(
        "{\"id\":\"festival_bathhouse_fire\",\"title\":\"湯祭り通りの火事場\",\"summary\":\"祭りで賑わう湯屋街が火を噴いた。群衆を避難させ、閉じ込められた湯屋番を救い、水門を開いて延焼を止める。\",\"party_setup\":{\"solo_friendly\":false,\"recommended_party_size\":{\"min\":2,\"max\":3},\"default_participants\":{\"2\":[\"alice\",\"bram\"],\"3\":[\"alice\",\"orion\",\"bram\"]},\"sample_pcs\":[\"alice\",\"orion\",\"bram\"]},\"opening_scene\":\"street\",\"goals\":[{\"id\":\"evacuate-crowd\",\"kind\":\"scene_progress_at_least\",\"scene\":\"street\",\"key\":\"evacuated\",\"value\":2,\"outcome\":\"success\"},{\"id\":\"save-attendant\",\"kind\":\"scene_flag\",\"scene\":\"bathhouse\",\"flag\":\"attendant_safe\",\"equals\":\"true\",\"outcome\":\"success\"},{\"id\":\"open-sluice\",\"kind\":\"scene_flag\",\"scene\":\"sluice\",\"flag\":\"channel_open\",\"equals\":\"true\",\"outcome\":\"success\"}],\"scenes\":{\"street\":{\"description\":\"祭囃子の残る湯祭り通り。屋台の布が燃え移り、湯気と煙の中で客たちが押し合いへし合いになっている。\",\"difficulty\":{\"stat\":\"body\",\"target\":9,\"tags\":[\"rescue\",\"crowd\",\"smoke\"]},\"transitions\":[{\"to\":\"bathhouse\",\"label\":\"湯屋の中へ踏み込む\",\"requires\":[{\"kind\":\"scene_progress_at_least\",\"scene\":\"street\",\"key\":\"evacuated\",\"value\":2}]}]},\"bathhouse\":{\"description\":\"蒸気が噴き上がる湯屋の内部。軋む梁の奥で湯屋番サザが配管に挟まれ、逃げ道を探している。\",\"difficulty\":{\"stat\":\"tech\",\"target\":9,\"tags\":[\"machinery\",\"steam\",\"rescue\"]},\"transitions\":[{\"to\":\"sluice\",\"label\":\"水門路へ走る\",\"requires\":[{\"kind\":\"scene_flag\",\"scene\":\"bathhouse\",\"flag\":\"attendant_safe\",\"equals\":\"true\"}]}]},\"sluice\":{\"description\":\"水路脇の大水門。石壁には古い操作手順が刻まれ、固着した歯車を力尽くと段取りで動かせば火勢を抑えられる。\",\"difficulty\":{\"stat\":\"body\",\"target\":11,\"tags\":[\"floodgate\",\"teamwork\",\"ancient-text\"]},\"transitions\":[]}},\"npcs\":[{\"name\":\"湯屋番 サザ\",\"kind\":\"npc\",\"sheet\":{\"name\":\"湯屋番 サザ\",\"class\":\"湯屋番\",\"stats\":{\"body\":1,\"tech\":2,\"mind\":1},\"hp_max\":7,\"traits\":[{\"id\":\"pipe-lore\",\"name\":\"配管知識\",\"desc\":\"蒸気配管や水門手順に関わる技判定で +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"machinery\",\"steam\",\"floodgate\"],\"trigger\":\"roll\"}]}],\"inventory\":[{\"id\":\"sluice-plaque\",\"name\":\"水門札\",\"desc\":\"古い水門の手順が刻まれた金属札\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"floodgate\",\"ancient-text\",\"teamwork\"]}]}]}}]}\n",
      )
    "midnight_auction" =>
      Some(
        "{\"id\":\"midnight_auction\",\"title\":\"真夜中の遺言競売\",\"summary\":\"豪商の遺産を巡る秘密競売。PC たちは同じ会場で協力して混乱を抑える必要があるが、誰に遺産を渡すかでは利害がぶつかる。\",\"interaction_mode\":\"mixed_interest\",\"party_setup\":{\"solo_friendly\":false,\"recommended_party_size\":{\"min\":3,\"max\":4},\"default_participants\":{\"3\":[\"alice\",\"orion\",\"mina\"],\"4\":[\"alice\",\"orion\",\"mina\",\"bram\"]},\"sample_pcs\":[\"alice\",\"orion\",\"mina\",\"bram\"]},\"opening_scene\":\"foyer\",\"goals\":[{\"id\":\"secure-ledger\",\"kind\":\"inventory_ever_contained\",\"actor\":\"any_pc\",\"item_id\":\"夜会台帳\",\"outcome\":\"success\"},{\"id\":\"expose-forgery\",\"kind\":\"scene_flag\",\"scene\":\"archive\",\"flag\":\"forgery_exposed\",\"equals\":\"true\",\"outcome\":\"success\"},{\"id\":\"avoid-riot\",\"kind\":\"scene_flag\",\"scene\":\"hearing\",\"flag\":\"riot_avoided\",\"equals\":\"true\",\"outcome\":\"success\"}],\"scenes\":{\"foyer\":{\"description\":\"仮面の客が集う夜会場の前室。招待状の真偽、客同士の腹の探り合い、遺言の噂で空気は張り詰めている。\",\"difficulty\":{\"stat\":\"mind\",\"target\":9,\"tags\":[\"parley\",\"deception\",\"crowd\"]},\"transitions\":[{\"to\":\"archive\",\"label\":\"控え室と記録庫へ入る\",\"requires\":[{\"kind\":\"scene_progress_at_least\",\"scene\":\"foyer\",\"key\":\"cover\",\"value\":2}]}]},\"archive\":{\"description\":\"競売場の裏手にある記録庫。帳簿、封蝋、差し替えられた遺言書の断片が散らばり、真偽を見抜けば誰に利があるかも見えてくる。\",\"difficulty\":{\"stat\":\"tech\",\"target\":9,\"tags\":[\"lockpick\",\"evidence\",\"observe\"]},\"transitions\":[{\"to\":\"hearing\",\"label\":\"公開審問と最終競売へ向かう\",\"requires\":[{\"kind\":\"scene_flag\",\"scene\":\"archive\",\"flag\":\"forgery_exposed\",\"equals\":\"true\"}]}]},\"hearing\":{\"description\":\"高壇の上では競売人が木槌を構え、後見人たちが怒号を飲み込んでいる。ここで誰に正統性を与えるかが、街の勢力図を決める。\",\"difficulty\":{\"stat\":\"mind\",\"target\":11,\"tags\":[\"bargain\",\"parley\",\"evidence\"]},\"transitions\":[]}},\"npcs\":[{\"name\":\"競売人 ヴァレル\",\"kind\":\"npc\",\"sheet\":{\"name\":\"競売人 ヴァレル\",\"class\":\"競売人\",\"stats\":{\"body\":0,\"tech\":1,\"mind\":2},\"hp_max\":7,\"traits\":[{\"id\":\"floor-control\",\"name\":\"場の支配\",\"desc\":\"公開審問や競売の流れを読む心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"bargain\",\"crowd\",\"parley\"],\"trigger\":\"roll\"}]}],\"inventory\":[]}},{\"name\":\"若後家 セラ\",\"kind\":\"npc\",\"sheet\":{\"name\":\"若後家 セラ\",\"class\":\"後見人\",\"stats\":{\"body\":0,\"tech\":0,\"mind\":2},\"hp_max\":6,\"traits\":[{\"id\":\"public-sympathy\",\"name\":\"同情の的\",\"desc\":\"涙と弁明で場を揺らす心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"parley\",\"deception\",\"crowd\"],\"trigger\":\"roll\"}]}],\"inventory\":[]}},{\"name\":\"組合代理 ハド\",\"kind\":\"npc\",\"sheet\":{\"name\":\"組合代理 ハド\",\"class\":\"代理人\",\"stats\":{\"body\":1,\"tech\":1,\"mind\":1},\"hp_max\":8,\"traits\":[{\"id\":\"hard-bargain\",\"name\":\"強硬交渉\",\"desc\":\"取引や圧力をかける心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"bargain\",\"parley\"],\"trigger\":\"roll\"}]}],\"inventory\":[]}},{\"name\":\"書記見習い ネロ\",\"kind\":\"npc\",\"sheet\":{\"name\":\"書記見習い ネロ\",\"class\":\"書記見習い\",\"stats\":{\"body\":0,\"tech\":2,\"mind\":1},\"hp_max\":6,\"traits\":[{\"id\":\"record-keeper\",\"name\":\"記録癖\",\"desc\":\"帳簿や封蝋を読む技判定で +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"evidence\",\"lockpick\",\"observe\"],\"trigger\":\"roll\"}]}],\"inventory\":[{\"id\":\"夜会台帳\",\"name\":\"夜会台帳\",\"desc\":\"裏帳簿。誰が本物の遺言を差し替えたかを示す記録。\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"evidence\",\"bargain\",\"parley\"]}]}]}}]}\n",
      )
    _ => None
  }
}

///|
fn bundled_template_text(id : String) -> String? {
  match id {
    "alice" =>
      Some(
        "{\"name\":\"alice\",\"class\":\"盗賊\",\"stats\":{\"body\":1,\"tech\":2,\"mind\":0},\"hp_max\":8,\"traits\":[{\"id\":\"lockpick\",\"name\":\"錠開け\",\"desc\":\"解錠・罠解除の技判定で +1\",\"effects\":[{\"stat\":\"tech\",\"amount\":1,\"tags\":[\"forced-entry\",\"lockpick\",\"trap\"],\"trigger\":\"roll\"}]},{\"id\":\"night-vision\",\"name\":\"夜目\",\"desc\":\"暗所の観察や索敵で不利を受けにくい\",\"effects\":[]}],\"inventory\":[{\"id\":\"dagger\",\"name\":\"短剣\",\"desc\":\"護身用の短剣\",\"effects\":[]},{\"id\":\"lantern\",\"name\":\"ランタン\",\"desc\":\"暗所を照らす油灯\",\"effects\":[]},{\"id\":\"rope\",\"name\":\"縄\",\"desc\":\"足場確保や回収に使う丈夫な縄\",\"effects\":[]}]}\n",
      )
    "orion" =>
      Some(
        "{\"name\":\"orion\",\"class\":\"学者\",\"stats\":{\"body\":0,\"tech\":1,\"mind\":2},\"hp_max\":7,\"traits\":[{\"id\":\"ancient-script\",\"name\":\"古文書読解\",\"desc\":\"古代語や魔術記号を読む心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"ancient-text\",\"ritual\",\"seal\"],\"trigger\":\"roll\"}]},{\"id\":\"careful\",\"name\":\"慎重\",\"desc\":\"危険な仕掛けを見落としにくい\",\"effects\":[]}],\"inventory\":[{\"id\":\"quill\",\"name\":\"羽根ペン\",\"desc\":\"記録用の羽根ペン\",\"effects\":[]},{\"id\":\"parchment\",\"name\":\"羊皮紙\",\"desc\":\"記録や写本に使う羊皮紙\",\"effects\":[]},{\"id\":\"small-knife\",\"name\":\"小型ナイフ\",\"desc\":\"護身と細工用の小刃\",\"effects\":[]}]}\n",
      )
    "bram" =>
      Some(
        "{\"name\":\"bram\",\"class\":\"運び屋\",\"stats\":{\"body\":2,\"tech\":1,\"mind\":0},\"hp_max\":9,\"traits\":[{\"id\":\"heavy-lifter\",\"name\":\"怪力\",\"desc\":\"救助や瓦礫どかし、水門操作の体判定で +1\",\"effects\":[{\"stat\":\"body\",\"amount\":1,\"tags\":[\"rescue\",\"debris\",\"floodgate\"],\"trigger\":\"roll\"}]},{\"id\":\"steady-feet\",\"name\":\"踏ん張り\",\"desc\":\"滑る床や悪い足場でも体勢を崩しにくい\",\"effects\":[]}],\"inventory\":[{\"id\":\"crowbar\",\"name\":\"てこ棒\",\"desc\":\"こじ開けや持ち上げに使う鉄の棒\",\"effects\":[]},{\"id\":\"work-gloves\",\"name\":\"作業手袋\",\"desc\":\"熱や擦り傷から手を守る厚手の手袋\",\"effects\":[]},{\"id\":\"canvas-sling\",\"name\":\"荷締め布\",\"desc\":\"荷物の固定や負傷者の搬送に使える丈夫な布\",\"effects\":[]}]}\n",
      )
    "mina" =>
      Some(
        "{\"name\":\"mina\",\"class\":\"弁士\",\"stats\":{\"body\":0,\"tech\":1,\"mind\":2},\"hp_max\":7,\"traits\":[{\"id\":\"silver-tongue\",\"name\":\"話術\",\"desc\":\"交渉、説得、取引の心判定で +1\",\"effects\":[{\"stat\":\"mind\",\"amount\":1,\"tags\":[\"parley\",\"bargain\",\"deception\"],\"trigger\":\"roll\"}]},{\"id\":\"read-room\",\"name\":\"空気読み\",\"desc\":\"人混みや場の空気から、有利な流れを掴む\",\"effects\":[]}],\"inventory\":[{\"id\":\"calling-cards\",\"name\":\"名刺束\",\"desc\":\"紹介や口利きに使う名刺束\",\"effects\":[]},{\"id\":\"sealed-notebook\",\"name\":\"封印付き手帳\",\"desc\":\"貸し借りと弱みを控えた小さな手帳\",\"effects\":[]},{\"id\":\"perfume-vial\",\"name\":\"香油瓶\",\"desc\":\"印象操作や気付けに使う香油\",\"effects\":[]}]}\n",
      )
    _ => None
  }
}

///|
fn bundled_scenario_source(id : String) -> ScenarioSourceRow? raise TrpgFailure {
  match bundled_scenario_text(id) {
    Some(text) => {
      let scenario = parse_json(text, "bundled:\{id}")
      let scenario_id = scenario_id_from_json_or_fallback(scenario, id)
      Some({
        scenario_id,
        source_kind: "bundled",
        source_label: "bundled:\{scenario_id}",
        source_text: text,
        scenario,
        source_url: None,
      })
    }
    None => None
  }
}

///|
fn bundled_scenario_row(id : String) -> ScenarioInstallRow raise TrpgFailure {
  let source = match bundled_scenario_source(id) {
    Some(source) => source
    None =>
      fail(
        TrpgError::NotFound(
          "bundled scenario is not found: \{id}",
          Some("check the bundled scenario table"),
        ),
      )
  }
  scenario_install_row(
    source.scenario_id,
    "bundled:\{source.scenario_id}",
    source.scenario,
    Some(Json::object({ "origin": Json::string("bundled") })),
  )
}

///|
fn bundled_scenario_rows() -> Array[ScenarioInstallRow] raise TrpgFailure {
  bundled_scenario_ids().map(bundled_scenario_row)
}

///|
fn bundled_template_path(template_id : String) -> String raise TrpgFailure {
  scenarios_dir() + "/sample_pc_\{template_id}.json"
}
