import { readFileSync, writeFileSync } from "node:fs"

const artifact = JSON.parse(
  readFileSync(new URL("../out/ZeroIdRegistry.sol/ZeroIdRegistry.json", import.meta.url), "utf8"),
)
const bc = artifact.bytecode?.object
if (typeof bc !== "string" || !bc.startsWith("0x") || bc.length < 100) {
  throw new Error("ZeroIdRegistry bytecode missing")
}
const dest = new URL("../../veil-frontend/lib/zeroid/registry-bytecode.ts", import.meta.url)
writeFileSync(dest, `export const ZEROID_REGISTRY_BYTECODE = "${bc}" as \`0x\${string}\`\n`)
const issue = artifact.methodIdentifiers?.["issue(bytes32,bytes32,bytes32,bytes32)"]
console.log("bytecode bytes", (bc.length - 2) / 2)
console.log("issue(bytes32,bytes32,bytes32,bytes32)", issue || "missing")
