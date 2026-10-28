// Entry for the iOS build of the desktop's dogma engine (canopus-desktop src/main/dogma): the same code
// the desktop runs, bundled for JavaScriptCore. Swift adds the SDE data it needs (addData, merged into one
// in-memory database kept between calculations) and calls the functions below; JSON in, JSON out.
// build.mjs points the modules' `../sde` and `./index` imports at shim-sde.ts / shim-index.ts.
import { abyssPlan } from '../../../canopus-desktop/src/main/dogma/abyss'
import { skillGains } from '../../../canopus-desktop/src/main/dogma/gains'
import { fitMetrics } from '../../../canopus-desktop/src/main/dogma/metrics'
import { npcDamage } from '../../../canopus-desktop/src/main/dogma/npc'
import { calculate } from '../../../canopus-desktop/src/main/dogma/stats'
import { db } from './db'

type Part = 'types' | 'groups' | 'attributes' | 'effects' | 'dogma'
const P = JSON.parse
const J = JSON.stringify

;(globalThis as Record<string, unknown>).CanopusDogma = {
  addData: (json: string): void => {
    const d = P(json) as Partial<Record<Part, Record<string, unknown>>>
    for (const k of ['types', 'groups', 'attributes', 'effects', 'dogma'] as Part[]) if (d[k]) Object.assign(db[k] as object, d[k])
  },
  calculate: (spec: string, skills: string): string => J(calculate(db, P(spec), P(skills))),
  /** The optimizer's numbers for each spec of a JSON array (one call for all of a fit's variants). */
  metrics: (specs: string, skills: string): string => {
    const s = P(skills)
    return J((P(specs) as unknown[]).map((spec) => fitMetrics(calculate(db, spec as never, s))))
  },
  npcDamage: (spec: string, skills: string, faction: string): string => J(npcDamage(P(spec), P(skills), faction as never)),
  /** What each next level of every unmaxed skill would change on the fit. */
  skillGains: (spec: string, levels: string): string => J(skillGains(P(spec), P(levels))),
  abyssPlan: (spec: string, skills: string, weather: string, strength: number): string => J(abyssPlan(P(spec), P(skills), weather as never, strength))
}
