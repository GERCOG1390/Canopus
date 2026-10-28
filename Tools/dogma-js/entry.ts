// Entry for the iOS build of the desktop's dogma engine (canopus-desktop src/main/dogma): the same code
// the desktop runs, bundled for JavaScriptCore. Swift passes JSON in and gets JSON back.
import { calculate } from '../../../canopus-desktop/src/main/dogma/stats'

;(globalThis as Record<string, unknown>).CanopusDogma = {
  calculate: (db: string, spec: string, skills: string): string => JSON.stringify(calculate(JSON.parse(db), JSON.parse(spec), JSON.parse(skills)))
}
