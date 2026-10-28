// Entry for the iOS build of the desktop's dogma engine (canopus-desktop src/main/dogma): the same code
// the desktop runs, bundled for JavaScriptCore. Swift adds the SDE data it needs (addData, merged into one
// in-memory database kept between calculations) and asks for a fit's stats; JSON in, JSON out.
import { calculate } from '../../../canopus-desktop/src/main/dogma/stats'
import type { SdeDb } from '../../../canopus-desktop/src/shared/sde'

const db = { types: {}, groups: {}, attributes: {}, effects: {}, dogma: {} } as unknown as SdeDb
type Part = 'types' | 'groups' | 'attributes' | 'effects' | 'dogma'

;(globalThis as Record<string, unknown>).CanopusDogma = {
  addData: (json: string): void => {
    const d = JSON.parse(json) as Partial<Record<Part, Record<string, unknown>>>
    for (const k of ['types', 'groups', 'attributes', 'effects', 'dogma'] as Part[]) if (d[k]) Object.assign(db[k] as object, d[k])
  },
  calculate: (spec: string, skills: string): string => JSON.stringify(calculate(db, JSON.parse(spec), JSON.parse(skills)))
}
