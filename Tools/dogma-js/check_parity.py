#!/usr/bin/env python3
"""Runs the bundled engine (Canopus/Resources/canopus-dogma.js) on EFT fits with the iOS app's own SDE
(Canopus/Resources/sde.sqlite), building the engine's data the way the app does (Canopus/App/DogmaJS.swift),
and prints one JSON line per fit in the desktop's comparison format (the Pyfa differential test).

    python3 Tools/dogma-js/check_parity.py fits.eft [environment type id ...] > canopus_ios.jsonl
"""
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DB = sqlite3.connect(os.environ.get('CANOPUS_SDE') or os.path.join(ROOT, 'Canopus/Resources/sde.sqlite'))
BUNDLE = os.path.join(ROOT, 'Packages/EVEStaticData/Sources/EVEStaticData/Resources/canopus-dogma.js')

SLOT_EFFECTS = [(12, 'hi'), (13, 'med'), (11, 'lo'), (2663, 'rig'), (3772, 'sub')]
CHARACTER_TYPE = 1373


def q(sql, *args):
    return DB.execute(sql, args).fetchall()


def type_by_name(name):
    r = q('select id from types where lower(name)=lower(?) order by published desc limit 1', name.strip())
    return r[0][0] if r else None


def category(type_id):
    r = q('select g.category_id from types t join groups g on g.id=t.group_id where t.id=?', type_id)
    return r[0][0] if r else None


def effects_of(type_id):
    return [e for (e,) in q('select effect_id from type_effects where type_id=?', type_id)]


def attrs_of(type_id):
    return dict(q('select attribute_id, value from type_attributes where type_id=?', type_id))


# ---------- data for the engine (mirrors DogmaJS.swift) ----------

def build_db(type_ids):
    """The SdeDb subset the engine reads: these types plus every skill, subsystem and tactical mode."""
    ids = set(type_ids) | {CHARACTER_TYPE}
    ids |= {i for (i,) in q('select t.id from types t join groups g on g.id=t.group_id where g.category_id in (16, 32) or t.group_id=1306')}
    types, dogma, effect_ids = {}, {}, set()
    for (tid, gid, name, pub, mass, vol, cap) in q(f'select id, group_id, name, published, mass, volume, capacity from types where id in ({",".join(map(str, ids))})'):
        t = {'id': tid, 'n': [name, name], 'g': gid, 'pub': bool(pub)}
        if mass is not None: t['mass'] = mass
        if vol is not None: t['vol'] = vol
        if cap is not None: t['cap'] = cap
        types[tid] = t
    for (tid, aid, v) in q(f'select type_id, attribute_id, value from type_attributes where type_id in ({",".join(map(str, ids))})'):
        dogma.setdefault(tid, {'a': {}, 'e': []})['a'][aid] = v
    for (tid, eid, de) in q(f'select type_id, effect_id, is_default from type_effects where type_id in ({",".join(map(str, ids))})'):
        d = dogma.setdefault(tid, {'a': {}, 'e': []})
        d['e'].append(eid)
        if de: d['de'] = eid
        effect_ids.add(eid)
    effects = {}
    for (eid, name, cat, dur, dis, rng, fall) in q(f'select id, name, effect_category, duration_attribute_id, discharge_attribute_id, range_attribute_id, falloff_attribute_id from dogma_effects where id in ({",".join(map(str, effect_ids))})'):
        e = {'name': name, 'cat': cat, 'mods': []}
        for k, v in (('dur', dur), ('dis', dis), ('range', rng), ('falloff', fall)):
            if v: e[k] = v
        effects[eid] = e
    for (eid, dom, func, grp, attr, src, op, skill) in q(f'select effect_id, domain, func, group_id, modified_attr_id, modifying_attr_id, operation, skill_type_id from dogma_modifiers where effect_id in ({",".join(map(str, effect_ids))}) order by id'):
        m = {'domain': dom, 'func': func, 'attr': attr, 'src': src, 'op': op}
        if grp is not None: m['group'] = grp
        if skill is not None: m['skill'] = skill
        effects[eid]['mods'].append(m)
    groups = {gid: {'n': [n, n], 'c': c, 'pub': bool(p)} for (gid, c, n, p) in q('select id, category_id, name, published from groups')}
    attributes = {aid: {'name': n, 'pub': bool(p), 'high': bool(h), 'def': d or 0, 'stack': bool(s)} for (aid, n, p, h, d, s) in q('select id, name, published, high_is_good, default_value, stackable from dogma_attributes')}
    return {'types': types, 'groups': groups, 'attributes': attributes, 'effects': effects, 'dogma': dogma}


# ---------- EFT → FitSpec (the desktop's fromEft rules) ----------

def default_state(type_id):
    effs = effects_of(type_id)
    rows = q(f'select effect_category, duration_attribute_id from dogma_effects where id in ({",".join(map(str, effs)) or "0"})')
    act = any(c in (1, 2) and d for c, d in rows)
    burst = bool(attrs_of(type_id).get(1014))  # disallowRepeatingActivation
    return 'active' if act and not burst else 'online'


def parse_eft(block):
    lines = [l.strip() for l in block.strip().split('\n')]
    head = re.match(r'^\[(.+?),\s*(.*)\]$', lines[0])
    ship = type_by_name(head.group(1))
    modes = {n.lower(): i for (i, n) in q('select id, name from types where group_id=1306')}
    fit = {'shipTypeId': ship, 'name': head.group(2), 'modules': [], 'drones': [], 'implants': []}
    for line in lines[1:]:
        if not line or re.match(r'^\[empty .+ slot\]$', line, re.I):
            continue
        if line.lower() in modes:
            fit['mode'] = modes[line.lower()]
            continue
        dm = re.match(r'^(.+?) x(\d+)$', line)
        if dm:
            tid = type_by_name(dm.group(1))
            if tid and category(tid) == 18:
                n = int(dm.group(2))
                fit['drones'].append({'typeId': tid, 'count': n, 'active': n})
            continue
        parts = [p.strip() for p in line.split(',')]
        tid = type_by_name(parts[0])
        if not tid:
            raise ValueError('unknown ' + parts[0])
        cat = category(tid)
        if cat == 20:
            fit['implants'].append(tid)
            continue
        effs = effects_of(tid)
        slot = next((s for e, s in SLOT_EFFECTS if e in effs), None)
        if not slot:
            continue
        m = {'typeId': tid, 'slot': slot, 'state': default_state(tid)}
        if len(parts) > 1:
            m['chargeTypeId'] = type_by_name(parts[1])
        fit['modules'].append(m)
    return fit


def main():
    blocks = [b for b in open(sys.argv[1], encoding='utf-8').read().split('\n---\n') if b.strip().startswith('[')]
    envs = [int(x) for x in sys.argv[2:]] or [0]
    jobs = []
    for env in envs:
        for b in blocks:
            fit = parse_eft(b)
            if env:
                fit['environment'] = env
            ids = [fit['shipTypeId'], *[m['typeId'] for m in fit['modules']], *[m['chargeTypeId'] for m in fit['modules'] if m.get('chargeTypeId')],
                   *[d['typeId'] for d in fit['drones']], *fit['implants'], *([fit['mode']] if fit.get('mode') else []), *([env] if env else [])]
            jobs.append({'name': b.strip().split('\n')[0] + (f'@{env}' if env else '@0'), 'db': build_db(ids), 'spec': fit})
    with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
        json.dump(jobs, f)
        path = f.name
    runner = r'''
const fs = require('fs'); eval(fs.readFileSync(process.argv[1], 'utf8'));
const r2 = (x) => Math.round(x * 100) / 100
for (const j of JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))) {
  try {
    CanopusDogma.addData(JSON.stringify(j.db)); const s = JSON.parse(CanopusDogma.calculate(JSON.stringify(j.spec), JSON.stringify({ mode: 'all5' })))
    const d = s.defense, res = (l) => l.resist.map((x) => Math.round(x * 10000) / 100)
    console.log(JSON.stringify({ name: j.name, dps: r2(s.offense.totalDps), volley: r2(s.offense.totalVolley), ehp: Math.round(d.ehp * 10) / 10,
      shield_res: res(d.shield), armor_res: res(d.armor), hull_res: res(d.hull), shield_hp: d.shield.hp, armor_hp: d.armor.hp, hull_hp: d.hull.hp,
      speed: r2(s.navigation.maxVelocity), sig: r2(s.navigation.signatureRadius), align: Math.round(s.navigation.alignSec * 1000) / 1000,
      lock: s.targeting.maxRange, scanres: s.targeting.scanResolution, cpu: [r2(s.ship.cpu.used), r2(s.ship.cpu.total)], pg: [r2(s.ship.power.used), r2(s.ship.power.total)],
      cap: s.capacitor.capacity, cap_recharge: s.capacitor.rechargeSec * 1000, cap_stable: s.capacitor.stable,
      cap_state: s.capacitor.stable ? Math.round((s.capacitor.stableLevel ?? 0) * 10000) / 100 : s.capacitor.lastsSec,
      cap_used: Math.round(s.capacitor.usePerSecond * 1000) / 1000, cap_peak: Math.round(s.capacitor.peakRecharge * 1000) / 1000,
      shield_rep: r2(d.shieldBoost), armor_rep: r2(d.armorRepair), hull_rep: r2(d.hullRepair), problems: s.problems }))
  } catch (e) { console.log(JSON.stringify({ name: j.name, error: String(e) })) }
}'''
    subprocess.run(['node', '-e', runner, BUNDLE, path], check=True)
    os.unlink(path)


if __name__ == '__main__':
    main()
