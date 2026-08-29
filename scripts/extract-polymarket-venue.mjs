import { readFileSync, writeFileSync } from "node:fs"

const artifact = JSON.parse(
  readFileSync(new URL("../out/PolymarketVenue.sol/PolymarketVenue.json", import.meta.url), "utf8"),
)
const bc = artifact.bytecode?.object
if (typeof bc !== "string" || !bc.startsWith("0x") || bc.length < 100) {
  throw new Error("PolymarketVenue bytecode missing")
}
const dest = new URL("../../veil-frontend/lib/polymarket/venue-bytecode.ts", import.meta.url)
writeFileSync(dest, `export const POLYMARKET_VENUE_BYTECODE = "${bc}" as \`0x\${string}\`\n`)
console.log("bytecode bytes", (bc.length - 2) / 2)
