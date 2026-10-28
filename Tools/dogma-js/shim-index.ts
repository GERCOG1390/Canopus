// Stands in for canopus-desktop src/main/dogma/index.ts in the iOS bundle (the original also reads files
// and talks to Electron): the modules bundled here only need calculateFit.
import { calculate } from '../../../canopus-desktop/src/main/dogma/stats'
import type { FitSpec, FitStats, SkillSource } from '../../../canopus-desktop/src/shared/fit'
import { db } from './db'

export const calculateFit = (spec: FitSpec, skills: SkillSource, extraShipAttrs?: number[]): FitStats => calculate(db, spec, skills, extraShipAttrs)
