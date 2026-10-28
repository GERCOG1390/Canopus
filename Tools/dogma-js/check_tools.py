#!/usr/bin/env python3
"""Checks the bundled NPC / abyss / optimizer / skill-gain functions with the iOS app's data against the same code fed
the desktop's whole SDE (same CCP build): the data the app adds for them must be enough.

    python3 Tools/dogma-js/check_tools.py fits.eft "<desktop sde-NNN.json>"
"""
import json
import os
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import check_parity as cp  # noqa: E402

FACTION_GROUP = {'guristas': 'Deadspace Guristas', 'serpentis': 'Deadspace Serpentis', 'blood_raiders': 'Deadspace Blood Raiders',
                 'sansha': "Deadspace Sansha's Nation", 'angel': 'Deadspace Angel Cartel', 'rogue_drones': 'Deadspace Rogue Drone',
                 'amarr': 'Mission Amarr Empire', 'caldari': 'Mission Caldari State', 'gallente': 'Mission Gallente Federation',
                 'minmatar': 'Mission Minmatar Republic', 'khanid': 'Mission Khanid', 'thukker': 'Mission Thukker',
                 'mordu': 'Mission Mordu', 'concord': 'Mission CONCORD'}
CLASSES = ['frigate', 'destroyer', 'cruiser', 'battlecruiser', 'battleship']


def npc_type_ids(faction):
    """Mirrors SDERepository.npcTypeIds(faction:)."""
    names = [f'{FACTION_GROUP[faction]} {c}'.lower() for c in CLASSES]
    marks = ','.join('?' * len(names))
    return [i for (i,) in cp.q(f'select t.id from types t join groups g on g.id=t.group_id where lower(g.name) in ({marks})', *names)]


def abyss_type_ids():
    """Mirrors SDERepository.abyssNpcTypeIds(): the abyssal NPC groups and the missiles they fire."""
    npcs = [i for (i,) in cp.q('select id from types where group_id in (1982, 1997)')]
    marks = ','.join(map(str, npcs))
    missiles = [int(v) for (v,) in cp.q(f'select value from type_attributes where attribute_id=507 and type_id in ({marks})')]
    return npcs + missiles


def main():
    fits = [b for b in open(sys.argv[1], encoding='utf-8').read().split('\n---\n') if b.strip().startswith('[')][:12]
    desktop = sys.argv[2]
    jobs = []
    for b in fits:
        spec = cp.parse_eft(b)
        ids = [spec['shipTypeId'], *[m['typeId'] for m in spec['modules']], *[m['chargeTypeId'] for m in spec['modules'] if m.get('chargeTypeId')],
               *[d['typeId'] for d in spec['drones']], *spec['implants'], *([spec['mode']] if spec.get('mode') else [])]
        jobs.append({'name': b.strip().split('\n')[0], 'spec': spec, 'ids': ids})
    extra = {'npc': npc_type_ids('guristas') + npc_type_ids('sansha'), 'abyss': abyss_type_ids() + [47381, 47382, 47383, 47390, 47391, 47392]}
    with tempfile.TemporaryDirectory() as tmp:
        ios = []
        for j in jobs:
            ios.append({'name': j['name'], 'spec': j['spec'], 'db': cp.build_db(j['ids'] + extra['npc'] + extra['abyss'])})
        json.dump(ios, open(os.path.join(tmp, 'ios.json'), 'w'))
        runner = r'''
const fs = require('fs')
const run = (dbs) => {
  const out = []
  const ctx = {}; eval(fs.readFileSync(process.argv[1], 'utf8').replace('globalThis', 'ctx'))
  const D = ctx.CanopusDogma
  let n = 0
  for (const j of JSON.parse(fs.readFileSync(process.argv[2], 'utf8'))) {
    if (dbs === 'desktop') { if (!D._loaded) { D.addData(fs.readFileSync(process.argv[3], 'utf8')); D._loaded = true } } else D.addData(JSON.stringify(j.db))
    const sk = JSON.stringify({ mode: 'all5' }), sp = JSON.stringify(j.spec)
    out.push({ name: j.name, npc: [D.npcDamage(sp, sk, 'guristas'), D.npcDamage(sp, sk, 'sansha')], abyss: [D.abyssPlan(sp, sk, 'electrical', 50), D.abyssPlan(sp, sk, 'firestorm', 70)], metrics: D.metrics(JSON.stringify([j.spec]), sk), gains: n++ < 3 ? D.skillGains(sp, JSON.stringify({ 3300: 4, 3319: 3, 3426: 2 })) : null })
  }
  return out
}
const a = run('ios'), b = run('desktop')
let diff = 0
a.forEach((x, i) => { for (const k of ['npc', 'abyss', 'metrics', 'gains']) if (JSON.stringify(x[k]) !== JSON.stringify(b[i][k])) { diff++; console.log('DIFF', x.name, k) } })
console.log(`${a.length} fits × 5 reports (+ skill gains on 3), ${diff} differences; gains rows on fit 1: ${JSON.parse(a[0].gains).length}`)
console.log(JSON.parse(a[0].npc[0]).classes.map((c) => c.cls + ' ' + c.count + ' ' + Math.round(c.ttkMedian) + 's').join(' | '))
console.log(JSON.parse(a[0].abyss[0]).factions.map((f) => f.faction + ' ' + f.npcs.length).join(' | '))
'''
        subprocess.run(['node', '-e', runner, cp.BUNDLE, os.path.join(tmp, 'ios.json'), desktop], check=True)


if __name__ == '__main__':
    main()
