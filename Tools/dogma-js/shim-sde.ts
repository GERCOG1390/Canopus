// Stands in for canopus-desktop src/main/sde in the iOS bundle: the dogma modules read the SDE through it.
import { db } from './db'

export const sdeForDogma = () => db
