"""Phase 2 (Knowledge Consolidation), phase 3 (Archive) and GUI tests."""
import math
import time
from pathlib import Path

CONS = "rd-consolidation-blue"  # tier II, active once chemical science is researched


def level_up(env, name):
    """Finish one level of a (finite or infinite) multi-level tech; `researched = true` would finish all levels."""
    env.lua(f'local t=game.forces.player.technologies["{name}"]; t.level = t.level + 1')


def level_down(env, name):
    env.lua(f'local t=game.forces.player.technologies["{name}"]; t.level = t.level - 1')


def phase2(env, t, vanilla=False):
    tag = "vanilla: " if vanilla else ""
    print(f"\n== Phase 2{' (vanilla)' if vanilla else ''}: Knowledge Consolidation tiers ==")
    s = env.status()
    step = s["step"]
    cfg = env.lua_json('remote.call("research-debt","config")')
    pct, bases = cfg["consolidation_percents"], cfg["consolidation_bases"]

    for name, levels in (("rd-consolidation-green", 8), ("rd-consolidation-blue", 10), ("rd-consolidation-yellow", 12), ("rd-consolidation-space", 4294967295)):
        info = env.lua_json(f'remote.call("research-debt","counts","{name}")')
        t.check(tag + f"{name} exists with {levels} levels and never counts", info and info["max_level"] == levels and not info["counts"], str(info))
        t.check(tag + f"{name} ignores the price multiplier", env.lua_json(f'prototypes.technology["{name}"].ignore_tech_cost_multiplier') is True)

    # nothing unlocked yet: no tier active
    env.lua('remote.call("research-debt","reset")')
    env.lua('for _,n in ipairs({"logistic-science-pack","chemical-science-pack"}) do game.forces.player.technologies[n].researched=false end')
    env.lua('remote.call("research-debt","recalculate")')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.check(tag + "no tier active before logistic science", cs.get("tier") is None, str(cs))

    # tier I with logistic science
    env.lua('game.forces.player.technologies["logistic-science-pack"].researched=true')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.check(tag + "tier I active after logistic science", cs.get("tier") == 1 and cs.get("available") is True, str({k: cs.get(k) for k in ("tier", "available", "name")}))
    t.check(tag + "tier I costs its base at level 1", cs["units"] == bases[0], f"units={cs['units']}")
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.approx(tag + "tier I value = 10% of 2.0 (or the floor)", cs["value"], max(s["consolidation_min"], pct[0] * 2.0))
    before = env.status()["debt"]
    level_up(env, "rd-consolidation-green")
    s2 = env.status()
    t.approx(tag + "tier I level removes its value", s2["debt"], before - cs["value"])
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.check(tag + "level 2 costs base x growth", cs["units"] == round(bases[0] * cfg["consolidation_growth"]) and cs["level"] == 2, f"level={cs['level']} units={cs['units']}")
    level_down(env, "rd-consolidation-green")
    t.approx(tag + "reversed level gives back exactly its amount", env.status()["debt"], before)

    # tier II replaces tier I
    env.lua('game.forces.player.technologies["chemical-science-pack"].researched=true')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.check(tag + "tier II active after chemical science", cs.get("tier") == 2 and cs["name"] == CONS, str({k: cs.get(k) for k in ("tier", "name")}))
    t.check(tag + "tier I disabled once tier II is unlocked", env.lua_json('game.forces.player.technologies["rd-consolidation-green"].enabled') is False)
    t.check(tag + "tier II starts at its own base cost", cs["units"] == bases[1], f"units={cs['units']}")
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.approx(tag + "tier II value = 15% of 2.0", cs["value"], max(s["consolidation_min"], pct[1] * 2.0))
    before = env.status()["debt"]
    level_up(env, CONS)
    s2 = env.status()
    t.approx(tag + "tier II level removes 15%", s2["debt"], before - cs["value"])
    t.check(tag + "stats.consolidation_levels counts the level", s2["stats"]["consolidation_levels"] == 1)
    t.approx(tag + "multiplier follows", s2["actual_multiplier"], s2["base_multiplier"] * (1 + s2["debt"]))

    # floor and minimum respected
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",0.1,"test")')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.approx(tag + "small debt: the floor applies", cs["value"], s["consolidation_min"])
    level_up(env, CONS)
    s2 = env.status()
    t.approx(tag + "consolidation never pushes debt below 0", s2["debt"], 0)
    t.approx(tag + "multiplier never below base", s2["actual_multiplier"], s2["base_multiplier"])

    # forgetting chemical science re-enables tier I
    env.lua('game.forces.player.technologies["chemical-science-pack"].researched=false')
    cs = env.lua_json('remote.call("research-debt","consolidation","player")')
    t.check(tag + "tier I active again after forgetting chemical science", cs.get("tier") == 1)
    env.lua('game.forces.player.technologies["chemical-science-pack"].researched=true')

    # debt from normal research is unaffected by consolidation bookkeeping
    env.lua('remote.call("research-debt","reset")')
    env.lua('game.forces.player.technologies["heavy-armor"].researched=false')
    env.lua('game.forces.player.technologies["heavy-armor"].researched=true')
    s2 = env.status()
    t.approx(tag + "normal research still adds its step after consolidation", s2["debt"],
             env.lua_json('remote.call("research-debt","step_for","heavy-armor").step'))


def phase3(env, t, vanilla=False):
    tag = "vanilla: " if vanilla else ""
    print(f"\n== Phase 3{' (vanilla)' if vanilla else ''}: Archive ==")
    exists = env.lua_json('prototypes.entity["rd-archive"] ~= nil')
    t.check(tag + "archive entity exists", exists)
    t.check(tag + "archive recipe/item/tech exist",
            env.lua_json('prototypes.recipe["rd-archive"] ~= nil and prototypes.item["rd-archive"] ~= nil and prototypes.technology["rd-archive"] ~= nil'))
    info = env.lua_json('remote.call("research-debt","counts","rd-archive")')
    t.check(tag + "archive tech does not count as debt", info and not info["counts"])

    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",3.0,"test")')
    bal = env.lua_json('remote.call("research-debt","balance")')
    H, dpp = bal["half_life"], bal["debt_per_point"]

    # place an archive via script (raise_built so the mod registers it)
    env.lua('storage.__t = game.surfaces[1].create_entity{name="rd-archive", position={3,3}, force="player", raise_built=true}')
    s = env.status()
    t.check(tag + "script-built archive is registered", s["archives"] == 1, f"archives={s['archives']}")

    # items without value stay
    env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="iron-plate", count=50}')
    env.lua("game.speed = 8")
    time.sleep(1.5)
    env.lua("game.speed = 1")
    left = env.lua_json('storage.__t.get_inventory(defines.inventory.chest).get_item_count("iron-plate")')
    t.check(tag + "items without value are not consumed", left == 50, f"left={left}")
    t.approx(tag + "no debt change from valueless items", env.status()["debt"], 3.0)

    # first offering: 100 processing units = 100 points
    v = env.lua_json('remote.call("research-debt","archive_value","processing-unit")')
    t.check(tag + "processing-unit has a value", v is not None and v > 0, str(v))
    pts = 100 * v
    expected1 = H * math.log((H + 0 + pts) / (H + 0)) * dpp
    before = env.status()["debt"]
    env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=100}')
    env.lua("game.speed = 8")
    time.sleep(1.5)
    env.lua("game.speed = 1")
    s = env.status()
    t.approx(tag + "first offering reduces debt by expected amount", before - s["debt"], expected1, 1e-6)
    t.check(tag + "offered items consumed", env.lua_json('storage.__t.get_inventory(defines.inventory.chest).get_item_count("processing-unit")') == 0)
    t.check(tag + "stats.archive_items == 100", s["stats"]["archive_items"] == 100)
    first = before - s["debt"]

    # second identical offering yields less (diminishing returns)
    before = s["debt"]
    env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=100}')
    env.lua("game.speed = 8")
    time.sleep(1.5)
    env.lua("game.speed = 1")
    s = env.status()
    second = before - s["debt"]
    expected2 = H * math.log((H + pts + pts) / (H + pts)) * dpp
    t.approx(tag + "second offering matches curve", second, expected2, 1e-6)
    t.check(tag + "second offering yields less than first", second < first, f"{first:.5f} -> {second:.5f}")

    # quality bonus (only when the quality mod is active)
    if env.lua_json('prototypes.quality["rare"] ~= nil'):
        qv = env.lua_json('remote.call("research-debt","archive_value","processing-unit","rare")')
        t.check(tag + "rare quality is worth more", qv > v, f"{v} -> {qv}")
        before = s["debt"]
        env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=10, quality="rare"}')
        env.lua("game.speed = 8")
        time.sleep(1.5)
        env.lua("game.speed = 1")
        s = env.status()
        got = before - s["debt"]
        T0 = 2 * pts
        exp_q = H * math.log((H + T0 + 10 * qv) / (H + T0)) * dpp
        t.approx(tag + "rare items reduce debt by quality-adjusted amount", got, exp_q, 1e-6)

    # robot-style removal and destruction must not error
    env.lua('storage.__t.destroy{raise_destroy=true}')
    s = env.status()
    t.check(tag + "destroyed archive is unregistered", s["archives"] == 0, f"archives={s['archives']}")
    # second archive, mined without raise (simulates nothing registering removal) -> stale handle cleaned on next sweep
    env.lua('storage.__t = game.surfaces[1].create_entity{name="rd-archive", position={6,3}, force="player", raise_built=true}')
    env.lua('storage.__t.destroy()')
    env.lua('remote.call("research-debt","archive_process_now")')
    s = env.status()
    t.check(tag + "stale archive handle cleaned up on sweep", s["archives"] == 0, f"archives={s['archives']}")
    env.lua('remote.call("research-debt","reset")')


def gui(env, t):
    print("\n== GUI: not implemented yet ==")


def place_lab_and_nest(env, lab=True):
    """Careful mode needs a lab of the force, lab waste needs an enemy nest on the surface."""
    env.lua('game.map_settings.enemy_expansion.enabled = false')
    if lab:
        env.lua('if game.surfaces[1].count_entities_filtered{name="lab", force="player"} == 0 then '
                'game.surfaces[1].create_entity{name="lab", position={-20,-20}, force="player"} end')
    env.lua('local s = game.surfaces[1] if s.count_entities_filtered{type="unit-spawner"} == 0 then '
            's.request_to_generate_chunks({96,96}, 1) s.force_generate_chunk_requests() '
            's.create_entity{name="biter-spawner", position={96,96}, force="enemy"} end')


def trades(env, t):
    print("\n== Trades: lab speed, evolution, forgetting ==")
    place_lab_and_nest(env)
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')

    def lab_net():
        # lab speed without the debt curve's own contribution (the curve changes as trades lower the debt)
        b = env.lua_json('remote.call("research-debt","bonus","player")')
        return b["lab_speed"] - b["applied"]
    lab0 = lab_net()

    ok = env.lua_json('remote.call("research-debt","trade_lab","player")')
    s = env.status()
    t.check("lab trade accepted", ok is True)
    t.approx("lab trade: modifier -0.10", lab_net(), lab0 - 0.10)
    t.approx("lab trade: debt -0.25", s["debt"], 1.75)
    for _ in range(4):
        env.lua('remote.call("research-debt","trade_lab","player")')
    ok6 = env.lua_json('remote.call("research-debt","trade_lab","player")')
    t.check("lab trade refused after 5 steps", ok6 is False)
    t.approx("lab trade: modifier -0.50 at max", lab_net(), lab0 - 0.50)
    t.approx("lab trade: debt -1.25 total", env.status()["debt"], 0.75)
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("lab penalty survives reset_technology_effects", lab_net(), lab0 - 0.50)
    ok = env.lua_json('remote.call("research-debt","trade_lab_undo","player")')
    t.check("lab undo accepted", ok is True)
    t.approx("lab undo: modifier -0.40", lab_net(), lab0 - 0.40)
    t.approx("lab undo: debt +0.25", env.status()["debt"], 1.0)
    ts = env.lua_json('remote.call("research-debt","trades_state","player")')
    t.check("trades_state reports 4 steps", ts["lab_steps"] == 4, str(ts))

    # evolution
    env.lua("game.forces.enemy.set_evolution_factor(0.5, game.surfaces[1])")
    before = env.status()["debt"]
    ok = env.lua_json('remote.call("research-debt","trade_evolution","player",1)')
    t.check("evolution trade accepted", ok is True)
    t.approx("evolution 0.50 -> 0.55", env.lua_json("game.forces.enemy.get_evolution_factor(game.surfaces[1])"), 0.55, 1e-4)
    t.approx("evolution trade: debt -0.25", env.status()["debt"], before - 0.25)
    env.lua("game.forces.enemy.set_evolution_factor(0.96, game.surfaces[1])")
    ok = env.lua_json('remote.call("research-debt","trade_evolution","player",1)')
    t.check("evolution trade refused at >= 0.95", ok is False)
    env.lua("game.forces.enemy.set_evolution_factor(0.0, game.surfaces[1])")

    # forgetting
    # make sure something is researched when this phase runs on its own
    env.lua('local f=game.forces.player; for _,n in ipairs({"logistics","military","steel-processing"}) do if f.technologies[n] then f.technologies[n].researched=true end end')
    names = env.lua_json('remote.call("research-debt","forgettable","player")')
    names = names if isinstance(names, list) else []
    t.check("there are forgettable technologies", len(names) > 0, f"{len(names)} forgettable: {names[:5]}")
    victim = names[0]
    all_free = env.lua_json(f'(function() for _,sc in pairs(game.forces.player.technologies["{victim}"].successors) do if sc.researched then return false end end return true end)()')
    t.check(f"{victim} has no researched successors", all_free is True)
    blocked = env.lua_json('(function() for n,tt in pairs(game.forces.player.technologies) do if tt.researched then for _,sc in pairs(tt.successors) do if sc.researched then return n end end end end return nil end)()')
    if blocked:
        t.check("tech with researched successor is not forgettable", blocked not in names, blocked)
        ok = env.lua_json(f'remote.call("research-debt","forget","player","{blocked}")')
        t.check("forget refused for tech with dependents", ok is False)
    before = env.status()
    ok = env.lua_json(f'remote.call("research-debt","forget","player","{victim}")')
    s = env.status()
    t.check("forget accepted", ok is True)
    t.check(f"{victim} is no longer researched", env.lua_json(f'game.forces.player.technologies["{victim}"].researched') is False)
    t.approx("forget: debt -step of that tech", s["debt"], before["debt"] - env.lua_json(f'remote.call("research-debt","step_for","{victim}").step'))
    t.check("forget: reversed counter incremented", s["stats"]["reversed"] == before["stats"]["reversed"] + 1)
    env.lua(f'game.forces.player.technologies["{victim}"].researched=true')
    env.lua('remote.call("research-debt","reset")')


def tiers(env, t):
    print("\n== Tiers: debt scales with science tier ==")
    s = env.status()
    base = s["step"]
    red = env.lua_json('remote.call("research-debt","step_for","automation")')
    t.check("automation is tier 1 (red)", red["tier"] == 1, str(red))
    t.approx("tier 1 step == 0.5 × base", red["step"], base * 0.5)
    blue = env.lua_json('remote.call("research-debt","step_for","advanced-electronics-2")')
    if blue:
        t.check("advanced-electronics-2 is tier 3 (blue)", blue["tier"] == 3, str(blue))
        t.approx("tier 3 step == 1.5 × base", blue["step"], base * 1.5)
    mil = env.lua_json('remote.call("research-debt","step_for","military-2")')
    t.check("military-2 is tier 2", mil["tier"] == 2, str(mil))
    env.lua('remote.call("research-debt","reset")')
    env.lua('local f=game.forces.player; f.technologies["automation"].researched=false; f.technologies["automation"].researched=true')
    t.approx("researching a red tech adds 0.5 × base", env.status()["debt"], base * 0.5)
    env.lua('remote.call("research-debt","recalculate")')
    n = env.lua_json('(function() local d=0 for _,tt in pairs(game.forces.player.technologies) do if tt.researched and remote.call("research-debt","counts",tt.name).counts then d=d+remote.call("research-debt","step_for",tt.name).step end end return d end)()')
    t.approx("recalculate uses tier-weighted steps", env.status()["debt"], n)


def bonus(env, t):
    print("\n== Lab speed curve, presets and milestones ==")
    cfg = env.lua_json('remote.call("research-debt","config")')
    t.check("standard preset active with veteran values", cfg["preset"] == "standard" and cfg["step"] == 0.1
            and cfg["penalty_threshold"] == 3.0 and cfg["penalty"] == 0.1 and cfg["max_multiplier"] == 50, str(cfg))
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')  # neutral zone: no modifier
    lab0 = env.lua_json("game.forces.player.laboratory_speed_modifier")

    def mod_at(debt):
        env.lua('remote.call("research-debt","reset")')
        if debt > 0:
            env.lua(f'remote.call("research-debt","add_debt",{debt},"test")')
        return env.lua_json("game.forces.player.laboratory_speed_modifier") - lab0

    for debt, want in ((0, 0.2), (0.3, 0.1), (0.8, 0.05), (2.0, 0.0), (3.5, -0.1), (6.0, -0.2)):
        t.approx(f"lab modifier at debt {debt} is {want:+.2f}", mod_at(debt), want)
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("penalty survives reset_technology_effects", env.lua_json("game.forces.player.laboratory_speed_modifier") - lab0, -0.2)
    env.lua('remote.call("research-debt","set_setting","rd-debt-free-bonus",0.5)')
    env.lua('remote.call("research-debt","reset")')
    t.approx("individual bonus setting is ignored under a preset", env.lua_json("game.forces.player.laboratory_speed_modifier") - lab0, 0.2)
    env.lua('remote.call("research-debt","set_setting","rd-debt-free-bonus",0.2)')
    curve = env.lua_json('remote.call("research-debt","lab_curve")')
    t.check("curve has 6 rows", len(curve) == 6, str([round(r["modifier"], 2) for r in curve]))

    # milestones: every 5 consolidation levels +2% lab productivity, permanent (levels of all tiers count)
    env.lua('for _,n in ipairs({"logistic-science-pack","chemical-science-pack","space-science-pack"}) do game.forces.player.technologies[n].researched=true end')
    env.lua('for _,n in ipairs({"rd-consolidation-green","rd-consolidation-blue","rd-consolidation-space"}) do game.forces.player.technologies[n].level = 1 end')
    prod0 = env.lua_json("game.forces.player.laboratory_productivity_bonus")
    INF = "rd-consolidation-space"  # infinite tier: ten levels fit
    env.lua('remote.call("research-debt","add_debt",5.0,"test")')
    for _ in range(5):
        level_up(env, INF)
    b = env.lua_json('remote.call("research-debt","bonus","player")')
    t.approx("5 consolidation levels: +0.05 lab productivity", b["lab_productivity"] - prod0, 0.05)
    for _ in range(5):
        level_up(env, INF)
    t.approx("10 levels: +0.10", env.lua_json("game.forces.player.laboratory_productivity_bonus") - prod0, 0.10)
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("productivity survives reset_technology_effects (native effect)", env.lua_json("game.forces.player.laboratory_productivity_bonus") - prod0, 0.10)
    for _ in range(4):
        level_down(env, INF)  # forget four levels: bonus drops to +0.06
    env.lua('game.forces.player.technologies["space-science-pack"].researched=false')
    t.approx("forgotten levels lower the milestone bonus", env.lua_json("game.forces.player.laboratory_productivity_bonus") - prod0, 0.06)
    env.lua('remote.call("research-debt","reset")')


def requests(env, t):
    print("\n== Archive requests ==")
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",3.0,"test")')
    bal = env.lua_json('remote.call("research-debt","balance")')
    H, dpp, bonus = bal["half_life"], bal["debt_per_point"], bal["request_bonus"]
    # unlock the processing-unit recipe whatever the technology is called in this mod set
    env.lua('for _,tech in pairs(game.forces.player.technologies) do for _,e in pairs(tech.prototype.effects) do '
            'if e.type=="unlock-recipe" and e.recipe=="processing-unit" then tech.researched=true end end end')
    t.check("processing-unit recipe unlocked", env.lua_json('game.forces.player.recipes["processing-unit"].enabled') is True)
    cands = env.lua_json('remote.call("research-debt","request_candidates")')
    t.check("candidates are producible value-table items", isinstance(cands, list) and "processing-unit" in cands and "spidertron" not in cands,
            f"{len(cands)} candidates")
    req = env.lua_json('remote.call("research-debt","new_request")')
    t.check("a random request is drawn", req is not None and req["amount"] >= bal["request_min"], str(req))
    req = env.lua_json('remote.call("research-debt","new_request","processing-unit",20)')
    t.check("explicit request processing-unit x20", req["item"] == "processing-unit" and req["amount"] == 20 and req["delivered"] == 0)

    env.lua('storage.__t = game.surfaces[1].create_entity{name="rd-archive", position={3,9}, force="player", raise_built=true}')
    total0 = env.status()["total_offered"]
    before = env.status()["debt"]
    env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=30}')
    env.lua("game.speed = 8")
    time.sleep(1.5)
    env.lua("game.speed = 1")
    s = env.status()
    pts = 20 * 1.0 * bonus + 10 * 1.0
    expected = H * math.log((H + total0 + pts) / (H + total0)) * dpp
    t.approx("20 requested items at 3x plus 10 at 1x", before - s["debt"], expected, 1e-6)
    t.check("request completed and cleared", env.lua_json('remote.call("research-debt","request")') is None)
    t.check("stats.requests_completed == 1", s["stats"]["requests_completed"] == 1)

    # queue of upcoming requests
    q = env.lua_json('remote.call("research-debt","request_queue")')
    t.check("3 upcoming requests are queued", isinstance(q, list) and len(q) == 3, str(q))
    head = q[0]
    env.lua('remote.call("research-debt","new_request")')
    req = env.lua_json('remote.call("research-debt","request")')
    t.check("head of the queue becomes the current request", req["item"] == head["item"] and req["amount"] == head["amount"], str(req))
    q2 = env.lua_json('remote.call("research-debt","request_queue")')
    t.check("queue refilled to 3", len(q2) == 3 and q2[0]["item"] == q[1]["item"], str(q2))

    # expiry draws a fresh request
    env.lua('remote.call("research-debt","new_request","processing-unit",50)')
    env.lua('storage.__t.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=5}')
    env.lua("game.speed = 8")
    time.sleep(1.2)
    env.lua("game.speed = 1")
    req = env.lua_json('remote.call("research-debt","request")')
    t.check("partial delivery tracked", req and req["delivered"] == 5, str(req))
    req2 = env.lua_json('remote.call("research-debt","expire_request")')
    t.check("expired request replaced by a new one", req2 is not None and req2["delivered"] == 0, str(req2))
    t.check("stats.requests_expired == 1", env.status()["stats"]["requests_expired"] == 1)

    # the interval comes from the preset; the individual setting is ignored unless the preset is Custom
    env.lua('remote.call("research-debt","set_setting","rd-request-interval",0)')
    t.check("request interval setting ignored under a preset", env.lua_json('remote.call("research-debt","config").request_interval') == 15)
    env.lua('remote.call("research-debt","set_setting","rd-request-interval",15)')
    env.lua('storage.__t.destroy{raise_destroy=true}')
    env.lua('remote.call("research-debt","reset")')


def labs(env, t):
    """Careful mode and the lab curve as hidden technologies: boundary cases and the 2.1.2 migration."""
    import io
    import subprocess
    import tarfile
    print("\n== Lab speed: boundaries, resets, migration ==")
    env.stop_server()
    env.write_mod_list(mod_enabled=True)
    env.install_mod()
    env.start_server(env.create_save("labs.zip"))

    def debt():
        return env.status()["debt"]

    def lab():
        return env.lua_json("game.forces.player.laboratory_speed_modifier")

    def levels():
        return env.lua_json('(function() local r={} for _,n in ipairs({"rd-lab-bonus","rd-lab-penalty","rd-careful-mode"}) do r[n]=game.forces.player.technologies[n].level-1 end return r end)()')

    # careful mode needs labs of the force's own; lab waste needs enemy nests on that surface
    env.lua('remote.call("research-debt","add_debt",1.0,"test")')
    t.check("careful mode refused without labs", env.lua_json('remote.call("research-debt","trade_lab","player")') is False)
    env.lua('if not game.surfaces["rd-empty"] then game.create_surface("rd-empty") end')
    empty = env.lua_json('game.surfaces["rd-empty"].index')
    t.check("lab waste refused on a surface without nests",
            env.lua_json(f'remote.call("research-debt","trade_evolution","player",{empty})') is False)
    place_lab_and_nest(env)
    t.check("lab waste accepted on a surface with a nest", env.lua_json('remote.call("research-debt","trade_evolution","player",1)') is True)
    env.lua("game.forces.enemy.set_evolution_factor(0, game.surfaces[1])")
    env.lua('remote.call("research-debt","reset")')

    # the archive leaves samples alone at debt 0 and books only what it really cleared
    env.lua('storage.__a = game.surfaces[1].create_entity{name="rd-archive", position={-30,-20}, force="player", raise_built=true}')
    env.lua('storage.__a.get_inventory(defines.inventory.chest).insert{name="processing-unit", count=10}')
    env.lua('remote.call("research-debt","archive_process_now")')
    t.check("archive keeps samples at debt 0", env.lua_json('storage.__a.get_inventory(defines.inventory.chest).get_item_count("processing-unit")') == 10)
    t.approx("archive books nothing at debt 0", env.status()["stats"]["archive_debt"], 0)
    env.lua('remote.call("research-debt","add_debt",0.01,"test")')
    env.lua('remote.call("research-debt","archive_process_now")')
    s = env.status()
    t.approx("archive books exactly what it cleared (never more than the 0.01 debt)", s["stats"]["archive_debt"], -(0.01 - s["debt"]))
    env.lua('storage.__a.destroy{raise_destroy=true}')
    env.lua('remote.call("research-debt","reset")')

    # careful mode clears at most what is left, and undo gives back exactly that
    env.lua('remote.call("research-debt","add_debt",0.13,"test")')
    env.lua('remote.call("research-debt","trade_lab","player")')
    t.approx("careful step at debt 0.13 clears 0.13", debt(), 0)
    t.check("careful step refused at debt 0", env.lua_json('remote.call("research-debt","trade_lab","player")') is False)
    env.lua('remote.call("research-debt","trade_lab_undo","player")')
    t.approx("undo gives back 0.13, not 0.25", debt(), 0.13)
    t.approx("trade stats back to 0", env.status()["stats"]["trades_debt"], 0)
    env.lua('remote.call("research-debt","trade_evolution","player",1)')
    t.approx("evolution trade at debt 0.13 books 0.13", env.status()["stats"]["trades_debt"], -0.13)
    env.lua("game.forces.enemy.set_evolution_factor(0, game.surfaces[1])")
    env.lua('remote.call("research-debt","reset")')

    # five steps at a debt in the neutral zone (curve 0): -0.50 carried by rd-careful-mode
    env.lua('remote.call("research-debt","add_debt",3.0,"test")')
    for _ in range(5):
        env.lua('remote.call("research-debt","trade_lab","player")')
    lv = levels()
    t.check("rd-careful-mode at level 5, curve techs at 0", lv == {"rd-lab-bonus": 0, "rd-lab-penalty": 0, "rd-careful-mode": 5}, str(lv))
    t.approx("five careful steps: lab modifier -0.50", lab(), -0.5)
    t.check("hidden techs stay disabled", env.lua_json('game.forces.player.technologies["rd-careful-mode"].enabled') is False)
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("survives reset_technology_effects", lab(), -0.5)
    env.lua("game.forces.player.research_all_technologies()")
    rs = env.lua_json('(function() local m=0 for _,tt in pairs(game.forces.player.technologies) do if tt.researched then for _,e in pairs(tt.prototype.effects) do if e.type=="laboratory-speed" and not tt.name:find("^rd%-") then m=m+e.modifier end end end end return m end)()')
    applied = env.lua_json('remote.call("research-debt","bonus","player").applied')
    t.approx("research_all_technologies: techs + curve - 0.50", lab(), rs + applied - 0.5)
    env.lua("game.forces.player.reset()")
    t.approx("force.reset(): debt derived again from what is researched (nothing)", debt(), 0)
    t.approx("survives force.reset()", lab(), env.lua_json('remote.call("research-debt","bonus","player").applied') - 0.5)
    env.lua('game.forces.player.technologies["rd-careful-mode"].level = 1')
    time.sleep(2)  # the 60-tick watchdog puts it back
    t.approx("someone else resetting rd-careful-mode is put back", lab(), env.lua_json('remote.call("research-debt","bonus","player").applied') - 0.5)
    env.stop_server(save_as="labs2")
    env.start_server(env.saves / "labs2.zip")
    t.approx("survives save and reload", lab(), env.lua_json('remote.call("research-debt","bonus","player").applied') - 0.5)
    for _ in range(5):
        env.lua('remote.call("research-debt","trade_lab_undo","player")')
    t.approx("all steps undone: careful level 0", levels()["rd-careful-mode"], 0)
    t.approx("all steps undone: trade stats 0", env.status()["stats"]["trades_debt"], 0)

    # merging a force gives back what its careful mode cleared
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')
    d0 = debt()
    env.lua('local b = game.forces["rd-b"] or game.create_force("rd-b") '
            'game.surfaces[1].create_entity{name="lab", position={-40,-20}, force=b}')
    env.lua('remote.call("research-debt","trade_lab","rd-b")')
    env.lua('remote.call("research-debt","trade_lab","rd-b")')
    t.approx("second force: two careful steps clear 0.50", debt(), d0 - 0.5)
    env.lua('game.merge_forces("rd-b", "player")')
    time.sleep(1)  # merging finishes at the end of the tick
    t.approx("merge: the careful reduction is given back", env.status()["stats"]["trades_debt"], 0)
    t.check("merge: no careful state left for rd-b", env.lua_json('game.forces["rd-b"] == nil') is True)

    # migration: a 2.1.2 save with careful steps and a curve bonus kept in laboratory_speed_modifier
    env.stop_server()
    for old in env.mods.glob("research-debt_*"):
        import shutil
        shutil.rmtree(old)
    blob = subprocess.run(["git", "archive", "57a102e", "research-debt"], cwd=str(Path(__file__).resolve().parent.parent),
                          capture_output=True, check=True).stdout
    dst = env.mods / "research-debt_2.1.2"
    with tarfile.open(fileobj=io.BytesIO(blob)) as tar:
        for m in tar.getmembers():
            if m.name.startswith("research-debt/") and m.isfile():
                out = dst / m.name[len("research-debt/"):]
                out.parent.mkdir(parents=True, exist_ok=True)
                out.write_bytes(tar.extractfile(m).read())
    env.start_server(env.create_save("old.zip"))
    env.lua('remote.call("research-debt","add_debt",1.55,"test")')
    for _ in range(5):
        env.lua('remote.call("research-debt","trade_lab","player")')
    old_lab = lab()
    t.approx("2.1.2 save: debt 0.30, curve +0.10, careful -0.50", old_lab, -0.4)
    env.stop_server(save_as="old")
    env.install_mod()
    env.start_server(env.saves / "old.zip")
    lv = levels()
    t.check("migrated: rd-lab-bonus 20 levels, careful 5", lv == {"rd-lab-bonus": 20, "rd-lab-penalty": 0, "rd-careful-mode": 5}, str(lv))
    t.approx("migrated: lab modifier unchanged (-0.40), not doubled", lab(), -0.4)
    env.lua('remote.call("research-debt","trade_lab_undo","player")')
    t.approx("migrated: undo gives back 0.25", debt(), 0.55)


def uninstall(env, t):
    """/rd-uninstall, then remove the mod: nothing of it may stay behind. /rd-set-base for a re-added mod."""
    print("\n== Uninstall and removal ==")
    env.stop_server()
    env.write_mod_list(mod_enabled=True)
    env.install_mod()
    env.start_server(env.create_save("uninstall.zip"))
    place_lab_and_nest(env)
    Q = ('{mult=game.difficulty_settings.technology_price_multiplier, lab=game.forces.player.laboratory_speed_modifier, '
         'prod=game.forces.player.laboratory_productivity_bonus}')
    base_lab = env.lua_json("game.forces.player.laboratory_speed_modifier") - env.lua_json('remote.call("research-debt","bonus","player").applied')
    env.lua('for _,n in ipairs({"logistic-science-pack","automation","logistics"}) do game.forces.player.technologies[n].researched=true end')
    env.lua('game.forces.player.technologies["rd-consolidation-green"].level = 4')
    env.lua('remote.call("research-debt","add_debt",3,"test")')
    for _ in range(3):
        env.lua('remote.call("research-debt","trade_lab","player")')
    with_mod = env.lua_json(Q)
    t.check("before uninstall: multiplier above 1", with_mod["mult"] > 1, str(with_mod))

    env.rcon.command("/rd-uninstall")
    t.approx("uninstall: multiplier back to base", env.lua_json(Q)["mult"], env.status()["base_multiplier"])
    time.sleep(2)
    t.approx("uninstall: watchdog keeps the base", env.lua_json(Q)["mult"], env.status()["base_multiplier"])
    env.rcon.command("/rd-uninstall cancel")
    t.approx("uninstall cancel: multiplier back", env.lua_json(Q)["mult"], with_mod["mult"])
    env.rcon.command("/rd-uninstall")
    env.stop_server(save_as="uninstall2")

    env.write_mod_list(mod_enabled=False)
    env.start_server(env.saves / "uninstall2.zip")
    gone = env.lua_json(Q)
    t.approx("removed: research cost multiplier 1", gone["mult"], 1)
    t.approx("removed: no lab speed left from the mod", gone["lab"], base_lab - 0)  # vanilla research-speed techs only
    t.approx("removed: no lab productivity left from the mod", gone["prod"], 0)

    # without /rd-uninstall the multiplier would stay; a re-added mod then warns and /rd-set-base fixes the base
    env.lua("game.difficulty_settings.technology_price_multiplier = 3")
    env.stop_server(save_as="uninstall3")
    env.write_mod_list(mod_enabled=True)
    env.start_server(env.saves / "uninstall3.zip")
    s = env.status()
    t.approx("re-added to a x3 save: base taken as 3", s["base_multiplier"], 3)
    env.rcon.command("/rd-set-base 1")
    s = env.status()
    t.approx("/rd-set-base 1: multiplier = 1 + debt", s["actual_multiplier"], 1 + s["debt"])
