import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import fs from "node:fs"
import vm from "node:vm"

const profilesSource = fs.readFileSync(new URL("../Profiles.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*/, "")
const profiles = {}
vm.createContext(profiles)
vm.runInContext(profilesSource, profiles)

for (const id of ["000000", "abc123", "abcdef", "123456"])
  assert.equal(profiles.profileId(id), id)

for (const id of ["", "abc12", "abc1234", "ABCDEF", "abcdeg", "abc-12", "$(id)", "../../"])
  assert.equal(profiles.profileId(id), "")

const manyProfiles = Array.from({ length: 40 }, (_, index) => ({
  id: index.toString(16).padStart(6, "0"),
  name: `Profile ${index}`
}))
assert.equal(profiles.normalize(manyProfiles).length, 32)
assert.equal(profiles.profileName("safe name", "abc123"), "safe name")
assert.equal(profiles.profileName("unsafe\u202ename", "abc123"), "abc123")
assert.equal(profiles.profileName("x".repeat(81), "abc123"), "abc123")

const service = fs.readFileSync(new URL("../NextDnsService.qml", import.meta.url), "utf8")
assert.doesNotMatch(service, /StdioCollector/)
assert.doesNotMatch(service, /\[\s*["'](?:nextdns|pkexec|sh|bash)["']/)
assert.match(service, /readonly property string nextdnsPath: "\/usr\/bin\/nextdns"/)
assert.match(service, /"\/usr\/bin\/pkexec"/)
assert.match(service, /"\/usr\/bin\/timeout"/)
assert.match(service, /"\/usr\/bin\/pacman", "-Qqo"/)
assert.match(service, /protectedPath/)
assert.match(service, /parts\[1\] !== "0"/)
assert.match(service, /--format=%n\|%u\|%a\|%F/)
assert.match(service, /"\/", "\/usr", "\/usr\/bin", root\.nextdnsPath/)
assert.doesNotMatch(service, /"--dereference"/)
assert.match(service, /mode & 0x12/)
assert.match(service, /mode & 0x49/)
assert.equal(parseInt("755", 8) & 0x12, 0)
assert.notEqual(parseInt("775", 8) & 0x12, 0)
assert.notEqual(parseInt("755", 8) & 0x49, 0)
assert.doesNotMatch(service, /--foreground/)
assert.match(service, /--kill-after=3s/)
assert.match(service, /splitMarker: ""/)
assert.match(service, /profileTransactionCommand/)
assert.match(service, /"\/usr\/bin\/env", "-i"/)
assert.match(service, /"\/usr\/bin\/bash", "--noprofile", "--norc"/)
assert.match(service, /trap rollback EXIT/)
assert.match(service, /previous profile was restored/)
assert.doesNotMatch(service, /id: (?:restart|rollback|rollbackRestart)Process/)

const transactionBody = service.match(
  /function profileTransactionCommand\([^)]*\) \{\s*var script = ""([\s\S]*?)\s*return \[/
)
assert.ok(transactionBody)
const transactionScript = [...transactionBody[1].matchAll(/\+\s+("(?:[^"\\]|\\.)*")/g)]
  .map((match) => JSON.parse(match[1]))
  .join("")
const syntaxCheck = spawnSync("/usr/bin/bash", ["-n", "-c", transactionScript], {
  encoding: "utf8"
})
assert.equal(syntaxCheck.status, 0, syntaxCheck.stderr)

console.log("security validation tests passed")
