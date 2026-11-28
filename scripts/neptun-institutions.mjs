// Builds Firka/Institutions.json: the universities whose new Neptun Web answers, for the login's list.
// Source: GreGamingHUN/Neptun-API's Institutes.json (MIT): names, OM codes and the old mobile addresses
// (…/MobileService.svc). Dropping that gives a candidate web address; each one is checked the way the app does it
// (Institution.discover: page, following a move, then assets/config/config.json) and only working ones are kept.
// Run: node scripts/neptun-institutions.mjs   (public files only, no login)
import { writeFileSync } from 'node:fs'

const source = 'https://raw.githubusercontent.com/GreGamingHUN/Neptun-API/main/Institutes.json'
const text = (await (await fetch(source)).text()).replace(/^﻿/, '')
// New Neptun Webs that moved away from the old address (checked like the rest)
const moved = {
  'Debreceni Egyetem': 'https://www-h-ng.neptun.unideb.hu/hallgato_ng/',
  'Óbudai Egyetem': 'https://neptun.uni-obuda.hu/ujhallgato/',
}
const list = JSON.parse(text)

async function check(web) {
  const get = (u) => fetch(u, { redirect: 'follow', signal: AbortSignal.timeout(10_000), headers: { 'user-agent': 'Mozilla/5.0' } })
  const page = await get(web)
  if (page.status !== 200) return null
  const base = page.url.endsWith('/') ? page.url : page.url.replace(/[^/]*$/, '')
  const r = await get(base + 'assets/config/config.json')
  if (r.status !== 200) return null
  try {
    const config = JSON.parse((await r.text()).replace(/^﻿/, '').trim())
    return config?.apiServer?.url ? base : null
  } catch { return null }
}

const out = []
const todo = list.filter((i) => i.Url)
for (let i = 0; i < todo.length; i += 6) {   // a few at a time
  await Promise.all(todo.slice(i, i + 6).map(async (inst) => {
    const web = moved[inst.Name.trim()] ?? inst.Url.replace(/MobileService\.svc\/?$/i, '')
    const ok = await check(web).catch(() => null)
    console.log(ok ? 'ok ' : '-- ', inst.Name, ok ?? web)
    if (ok) out.push({ name: inst.Name.trim(), omCode: inst.OMCode, web: ok })
  }))
}
out.sort((a, b) => a.name.localeCompare(b.name, 'hu'))
writeFileSync(new URL('../Firka/Institutions.json', import.meta.url), JSON.stringify(out, null, 1) + '\n')
console.log(`${out.length} of ${list.length} kept`)
