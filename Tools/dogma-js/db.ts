// The in-memory SdeDb the iOS app fills through CanopusDogma.addData (only what a calculation needs).
import type { SdeDb } from '../../../canopus-desktop/src/shared/sde'

export const db = { types: {}, groups: {}, attributes: {}, effects: {}, dogma: {} } as unknown as SdeDb
