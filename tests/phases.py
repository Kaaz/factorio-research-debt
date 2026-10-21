"""Phase 2 (Knowledge Consolidation), phase 3 (Archive) and GUI tests."""
import math
import time

CONS = "rd-consolidation-1"


def phase2(env, t, vanilla=False):
    tag = "vanilla: " if vanilla else ""
    print(f"\n== Phase 2{' (vanilla)' if vanilla else ''}: Knowledge Consolidation ==")
    s = env.status()
    x = s["consolidation_value"]
    step = s["step"]

    info = env.lua_json(f'remote.call("research-debt","counts","{CONS}")')
    t.check(tag + "consolidation tech exists, is infinite and never counts", info and info["infinite"] and not info["counts"])
    ignores = env.lua_json(f'prototypes.technology["{CONS}"].ignore_tech_cost_multiplier')
    t.check(tag + "consolidation ignores the price multiplier", ignores is True)

    # make sure there is debt to pay off
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')
    cost1 = env.lua_json(f'game.forces.player.technologies["{CONS}"].research_unit_count')
    t.check(tag + "level 1 costs 500 units regardless of multiplier", cost1 == 500, f"cost={cost1}")

    before = env.status()["debt"]
    env.lua(f'game.forces.player.technologies["{CONS}"].researched=true')
    s = env.status()
    t.approx(tag + "level 1 removes X debt", s["debt"], before - x)
    t.check(tag + "stats.consolidation_levels == 1", s["stats"]["consolidation_levels"] == 1)
    t.approx(tag + "multiplier follows", s["actual_multiplier"], s["base_multiplier"] * (1 + s["debt"]))
    lvl = env.lua_json(f'game.forces.player.technologies["{CONS}"].level')
    cost2 = env.lua_json(f'game.forces.player.technologies["{CONS}"].research_unit_count')
    t.check(tag + "level 2 costs more than level 1 (750)", cost2 == 750 and lvl == 2, f"level={lvl} cost={cost2}")

    # minimum respected
    env.lua('remote.call("research-debt","reset")')
    env.lua(f'remote.call("research-debt","add_debt",{x / 2},"test")')
    env.lua(f'game.forces.player.technologies["{CONS}"].researched=true')
    s = env.status()
    t.approx(tag + "consolidation never pushes debt below 0", s["debt"], 0)
    t.approx(tag + "multiplier never below base", s["actual_multiplier"], s["base_multiplier"])

    # debt from normal research is unaffected by consolidation bookkeeping
    env.lua('remote.call("research-debt","reset")')
    env.lua('game.forces.player.technologies["heavy-armor"].researched=false')
    env.lua('game.forces.player.technologies["heavy-armor"].researched=true')
    s = env.status()
    t.approx(tag + "normal research still adds its step after consolidation", s["debt"],
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


def trades(env, t):
    print("\n== Trades: lab speed, evolution, forgetting ==")
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",2.0,"test")')
    lab0 = env.lua_json("game.forces.player.laboratory_speed_modifier")

    ok = env.lua_json('remote.call("research-debt","trade_lab","player")')
    s = env.status()
    t.check("lab trade accepted", ok is True)
    t.approx("lab trade: modifier -0.10", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 - 0.10)
    t.approx("lab trade: debt -0.25", s["debt"], 1.75)
    for _ in range(4):
        env.lua('remote.call("research-debt","trade_lab","player")')
    ok6 = env.lua_json('remote.call("research-debt","trade_lab","player")')
    t.check("lab trade refused after 5 steps", ok6 is False)
    t.approx("lab trade: modifier -0.50 at max", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 - 0.50)
    t.approx("lab trade: debt -1.25 total", env.status()["debt"], 0.75)
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("lab penalty survives reset_technology_effects", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 - 0.50)
    ok = env.lua_json('remote.call("research-debt","trade_lab_undo","player")')
    t.check("lab undo accepted", ok is True)
    t.approx("lab undo: modifier -0.40", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 - 0.40)
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
    names = env.lua_json('remote.call("research-debt","forgettable","player")')
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
    print("\n== Debt-free bonus ==")
    env.lua('remote.call("research-debt","reset")')
    env.lua('remote.call("research-debt","add_debt",1.0,"test")')
    b = env.lua_json('remote.call("research-debt","bonus","player")')
    t.check("bonus inactive while in debt", b["active"] is False and b["applied"] == 0, str(b))
    lab0 = env.lua_json("game.forces.player.laboratory_speed_modifier")
    env.lua('remote.call("research-debt","add_debt",-1.0,"test")')
    b = env.lua_json('remote.call("research-debt","bonus","player")')
    t.check("bonus active at zero debt", b["active"] is True and abs(b["applied"] - b["amount"]) < 1e-9, str(b))
    t.approx("lab speed modifier +amount", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 + b["amount"])
    env.lua("game.forces.player.reset_technology_effects()")
    t.approx("bonus survives reset_technology_effects", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 + b["amount"])
    env.lua('remote.call("research-debt","set_setting","rd-debt-free-bonus",0.5)')
    t.approx("setting change re-applies exact amount", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0 + 0.5)
    env.lua('remote.call("research-debt","set_setting","rd-debt-free-bonus",0.2)')
    env.lua('local f=game.forces.player; f.technologies["heavy-armor"].researched=false; f.technologies["heavy-armor"].researched=true')
    t.approx("new debt removes the bonus", env.lua_json("game.forces.player.laboratory_speed_modifier"), lab0)
    b = env.lua_json('remote.call("research-debt","bonus","player")')
    t.check("bonus reported inactive again", b["active"] is False and b["applied"] == 0)
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

    # interval 0 disables
    env.lua('remote.call("research-debt","set_setting","rd-request-interval",0)')
    env.lua('remote.call("research-debt","reset")')
    env.lua("game.speed = 8")
    time.sleep(1.2)
    env.lua("game.speed = 1")
    t.check("interval 0: no request drawn", env.lua_json('remote.call("research-debt","request")') is None)
    env.lua('remote.call("research-debt","set_setting","rd-request-interval",15)')
    env.lua('storage.__t.destroy{raise_destroy=true}')
    env.lua('remote.call("research-debt","reset")')
