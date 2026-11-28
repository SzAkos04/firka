// Is a university's Neptun Web still the way Firka expects it? Public files only, no login.
// Reads the config file and the JS bundles, and lists which endpoints and token keys Firka relies on are still there.
// Run before a release: node scripts/neptun-check.mjs [web address]   (default: BME)
const web = (process.argv[2] ?? 'https://neptun.bme.hu/hallgatoi/').replace(/\/?$/, '/')
const get = async (u) => { const r = await fetch(u, { headers: { 'user-agent': 'Mozilla/5.0' } }); if (!r.ok) throw new Error(`${u}: HTTP ${r.status}`); return r }

const page = await get(web)
const base = page.url.endsWith('/') ? page.url : page.url.replace(/[^/]*$/, '')
const html = await page.text()
const config = JSON.parse((await (await get(base + 'assets/config/config.json')).text()).replace(/^﻿/, '').trim())
console.log(`${base}\n  API: ${new URL(config.apiServer.url, base)}`)

// every bundle the page loads, and the lazy chunks they name
const seen = new Set(), queue = [...html.matchAll(/src="([^"]+\.js)"/g)].map((m) => m[1])
let code = ''
while (queue.length) {
  const f = queue.shift()
  if (seen.has(f)) continue
  seen.add(f)
  const js = await (await get(base + f)).text()
  code += js
  for (const m of js.matchAll(/chunk-[A-Z0-9]+\.js/g)) if (!seen.has(m[0])) queue.push(m[0])
}
console.log(`  ${seen.size} bundles read`)

const expected = [
  'Account/Authenticate', 'Account/GetNewTokens', 'access_token', 'access_token_expiration_date', 'withCredentials',
  'TakenSubjects/Terms', 'SubjectCourse/GetSubjectDetails', 'Calendar/GetCalendarEvents', 'Message/GetReceivedMessages',
  'ExamRegisteredExams/GetRegisteredExamsList', 'ExamResults/GetExamResultsList', 'Advancement/GetTermAveragesByTraining',
]
let missing = 0
for (const k of expected) {
  const ok = code.includes(k)
  if (!ok) missing++
  console.log(`  ${ok ? 'ok     ' : 'MISSING'} ${k}`)
}
process.exit(missing ? 1 : 0)
