// Firka's notifications from the server: polls KRÉTA, works out what is new (a port of Notifier.changes in
// Firka/Store.swift), publishes it to ntfy. No dependencies. Why it exists: NTFY_PUSH_PLAN.md.
import { readFileSync, writeFileSync, renameSync, existsSync } from 'node:fs'
import { createServer } from 'node:http'
import { join } from 'node:path'

export const KRETA = {
  idp: 'https://idp.e-kreta.hu',
  api: (iss) => `https://${iss}.e-kreta.hu`,
  inbox: 'https://eugyintezes.e-kreta.hu',
  clientId: 'kreta-ellenorzo-student-mobile-ios',
  userAgent: 'eKretaStudent/264745 CFNetwork/1494.0.7 Darwin/23.4.0',
  apiKey: '21ff6c25-d1da-4a68-a811-c881a6057463',
}

export class Reauth extends Error {}
class Http extends Error {}

export const readJSON = (f, fallback) => { try { return JSON.parse(readFileSync(f, 'utf8')) } catch { return fallback } }
export const writeJSON = (f, v) => { writeFileSync(f + '.tmp', JSON.stringify(v), { mode: 0o600 }); renameSync(f + '.tmp', f) }

// --- session ---

export async function tokenRequest(form, k = KRETA) {
  const r = await fetch(`${k.idp}/connect/token`, {
    method: 'POST', body: new URLSearchParams(form),
    headers: { 'content-type': 'application/x-www-form-urlencoded; charset=UTF-8', 'user-agent': k.userAgent },
  })
  if (r.status === 400 || r.status === 401) throw new Reauth('KRÉTA refused the session')
  if (!r.ok) throw new Http(`token: HTTP ${r.status}`)
  return r.json()
}

function session(file, k) {
  let t = readJSON(file, null), renewing = null
  // Refresh tokens are single-use: one renewal at a time, and a request that failed with a token someone else
  // already replaced just retries with the new one.
  const renew = (used) => {
    if (t.accessToken !== used) return Promise.resolve()
    return (renewing ??= (async () => {
      const g = await tokenRequest({ institute_code: t.iss, refresh_token: t.refreshToken, grant_type: 'refresh_token', client_id: k.clientId }, k)
      t = { ...t, accessToken: g.access_token, refreshToken: g.refresh_token ?? t.refreshToken, expiry: Date.now() + (g.expires_in - 60) * 1000 }
      writeJSON(file, t)   // on disk before anything uses it: a crash must not lose the session
    })().finally(() => (renewing = null)))
  }
  async function get(url) {
    for (let attempt = 0; attempt < 2; attempt++) {
      if (t.expiry <= Date.now()) await renew(t.accessToken)
      const used = t.accessToken
      const r = await fetch(url, {
        headers: { accept: '*/*', 'user-agent': k.userAgent, authorization: `Bearer ${used}`, apiKey: k.apiKey },
        signal: AbortSignal.timeout(30_000),
      })
      if (r.status === 401) { if (attempt === 0) { await renew(used); continue } throw new Reauth('401 after a renewal') }
      if (!r.ok) throw new Http(`${new URL(url).pathname}: HTTP ${r.status}`)
      return r.json()
    }
  }
  return t && { get, iss: t.iss }
}

// --- fetching ---

const pad = (n) => String(n).padStart(2, '0')
const day = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x }
const monday = (now) => { const d = new Date(now); d.setHours(0, 0, 0, 0); return addDays(d, -((d.getDay() + 6) % 7)) }

/** What the diff needs, from KRÉTA. Grades and the timetable must succeed; the rest are null when they fail. */
async function fetchAll(s, now, k) {
  const list = (path, q) => s.get(`${k.api(s.iss)}/ellenorzo/v3/sajat/${path}${q ? '?' + new URLSearchParams(q) : ''}`)
  const soft = (p) => p.catch((e) => { if (e instanceof Reauth) throw e; console.error(String(e)); return null })
  // KRÉTA filters by the UTC date: ask from the day before and keep the week's own days (KretaClient.week).
  const week = async (start) => (await list('OrarendElemek', { datumTol: day(addDays(start, -1)), datumIg: day(addDays(start, 6)) }))
    .filter((o) => { const t = new Date(o.KezdetIdopont); return t >= start && t < addDays(start, 7) })
  const m = monday(now)
  const sept1 = new Date(now.getFullYear(), 8, 1), schoolStart = sept1 > now ? new Date(now.getFullYear() - 1, 8, 1) : sept1
  const [grades, w1, w2, absences, homework, tests, notices, notes, inbox] = await Promise.all([
    list('Ertekelesek'), week(m), week(addDays(m, 7)),
    soft(list('Mulasztasok')), soft(list('HaziFeladatok', { datumTol: day(schoolStart) })), soft(list('BejelentettSzamonkeresek')),
    soft(list('FaliujsagElemek')), soft(list('Feljegyzesek')),
    soft(s.get(`${k.inbox}/api/v1/kommunikacio/postaladaelemek/sajat`)),
  ])
  // three sources, each on its own: a failed one is null (the inbox lives on another host and fails apart)
  const messages = {
    n: notices?.map((n) => ({ id: 'n' + n.Uid, title: n.Cim ?? 'Üzenet' })),
    f: notes?.map((n) => ({ id: 'f' + n.Uid, title: n.Cim ?? n.Tipus?.Leiras ?? 'Feljegyzés' })),
    p: inbox?.filter((p) => p.tipus?.kod === 'BEERKEZETT' && p.isToroltElem !== true)
      .map((p) => ({ id: 'p' + p.azonosito, title: p.uzenet?.targy ?? 'Üzenet' })),
  }
  return { grades, lessons: [...w1, ...w2], absences, homework, tests, messages }
}

// --- what is new ---

const cap = (s) => s.slice(0, 1).toUpperCase() + s.slice(1)
const pick = (custom, original) => custom?.trim() || original
const weekday = new Intl.DateTimeFormat('hu-HU', { weekday: 'long' })
const when = (iso) => { const d = new Date(iso); return `${weekday.format(d)} ${pad(d.getHours())}:${pad(d.getMinutes())}` }

/**
 * The alerts between the last poll's state and new data, and the state to keep: ids, plus what a change of a known
 * item needs (grade values, substitute names, which absences are unexcused).
 * Same rules as the app: no alerts on the first poll, an empty list followed by a full one is a new baseline,
 * a kind that failed to load (null) keeps what was known.
 */
export function changes(old, d, now, prefs = {}) {
  const on = (key) => prefs.kinds?.[key] ?? true
  const surprise = prefs.surprise ?? true
  const subject = (nev) => pick(prefs.subjects?.[cap(nev)], cap(nev))
  const teacher = (n) => pick(prefs.teachers?.[n], n)
  const out = []
  const add = (id, one, many, ls) => { if (ls.length) out.push({ id, title: ls.length === 1 ? one : many(ls.length), lines: ls.slice(0, 5) }) }
  const fresh = (kind, items, idOf = (x) => x.Uid) => {
    const seen = old?.[kind]
    if (!items || !seen || (seen.length === 0 && items.length > 3)) return []
    return items.filter((x) => !seen.includes(idOf(x)))
  }
  const display = (g) => {
    if (g.ErtekFajta?.Nev === 'Osztalyzat' && g.SzamErtek != null) return `${g.SzamErtek}`
    if (g.ErtekFajta?.Nev === 'Szazalekos' && g.SzamErtek != null) return `${g.SzamErtek}%`
    return g.SzovegesErtekelesRovidNev ?? g.SzovegesErtek ?? '–'
  }
  const absence = (a) => {
    const late = a.Tipus?.Nev?.toLowerCase() === 'keses' || (a.KesesPercben ?? 0) > 0
    const kind = late ? `késés (${a.KesesPercben ?? 0} perc)` : 'hiányzás'
    return ({ Igazolt: 'Igazolt', Igazolatlan: 'Igazolatlan' }[a.IgazolasAllapota] ?? 'Igazolandó') + ' ' + kind
  }
  const cancelled = (o) => (o.Allapot?.Nev ?? '').toLowerCase().includes('elmarad') || o.Tipus?.Nev === 'UresOra'
  const title = (o) => subject(o.Tantargy?.Nev ?? o.Nev ?? 'Óra')

  if (on('notifyGrades')) {
    add('grades', 'Új jegy érkezett', (n) => `${n} új jegy érkezett`,
      fresh('grades', d.grades).map((g) => `${subject(g.Tantargy.Nev)}: ${surprise ? 'új jegy' : display(g)}`))
    // the same grade with another value: the teacher corrected it (no values kept before this: nothing to compare)
    add('edited', 'Módosult egy jegy', (n) => `${n} jegy módosult`, old?.values ? d.grades.flatMap((g) => {
      const before = old.values[g.Uid]
      return before === undefined || before === display(g) ? [] : [`${subject(g.Tantargy.Nev)}: ${surprise ? 'módosult' : `${before} → ${display(g)}`}`]
    }) : [])
  }
  if (on('notifyLessons') && old?.lessons) {
    const future = d.lessons.filter((o) => o.Tipus?.Nev !== 'TanevRendjeEsemeny' && new Date(o.VegIdopont) > now && !hidden(o, prefs.hidden))
    add('cancelled', 'Elmaradt óra', (n) => `${n} elmaradt óra`,
      future.filter((o) => cancelled(o) && !old.cancelled.includes(o.Uid)).map((o) => `${title(o)} – ${when(o.KezdetIdopont)}`))
    add('substituted', 'Helyettesítés', (n) => `${n} helyettesítés`,
      // subst was a list of uids before it kept the names: then only a lesson not in it is news
      future.filter((o) => !cancelled(o) && o.HelyettesTanarNeve &&
        (Array.isArray(old.subst) ? !old.subst.includes(o.Uid) : old.subst?.[o.Uid] !== o.HelyettesTanarNeve))
        .map((o) => `${title(o)}: ${teacher(o.HelyettesTanarNeve)} (${when(o.KezdetIdopont)})`))
  }
  if (on('notifyHomework')) {
    add('homework', 'Új házi feladat', (n) => `${n} új házi feladat`, fresh('homework', d.homework).map((h) => subject(h.Tantargy.Nev)))
    add('tests', 'Új számonkérés', (n) => `${n} új számonkérés`,
      fresh('tests', d.tests).map((t) => `${subject(t.Tantargy.Nev)}: ${t.Temaja ?? t.Modja?.Leiras ?? ''}`))
  }
  if (on('notifyAbsences')) {
    add('absences', 'Új hiányzás/késés', (n) => `${n} új hiányzás/késés`,
      fresh('absences', d.absences).map((a) => `${subject(a.Tantargy.Nev)}: ${absence(a)}`))
    // KRÉTA keeps the absence and changes its state; unexcused is the one that matters
    add('unexcused', 'Igazolatlan lett', (n) => `${n} mulasztás igazolatlan lett`, d.absences && old?.unexcused && old.absences ? d.absences
      .filter((a) => a.IgazolasAllapota === 'Igazolatlan' && old.absences.includes(a.Uid) && !old.unexcused.includes(a.Uid))
      .map((a) => `${subject(a.Tantargy.Nev)}: ${absence(a)}`) : [])
  }
  // Messages by source (the id's first letter): a source that failed keeps its ids; one never loaded before is a baseline.
  const loaded = Object.keys(d.messages).filter((src) => d.messages[src])
  const knew = old?.sources ?? (old?.messages ? ['n', 'f', 'p'] : [])
  const msgs = loaded.flatMap((src) => d.messages[src])
  if (on('notifyMessages')) {
    add('messages', 'Új üzenet', (n) => `${n} új üzenet`,
      fresh('messages', msgs.filter((m) => knew.includes(m.id[0])), (m) => m.id).map((m) => m.title))
  }

  const ids = (kind, items, idOf = (x) => x.Uid) => (items ? items.map(idOf) : old?.[kind] ?? null)
  const state = {
    grades: ids('grades', d.grades), homework: ids('homework', d.homework), tests: ids('tests', d.tests),
    absences: ids('absences', d.absences),
    messages: old?.messages || loaded.length ? [...msgs.map((m) => m.id), ...(old?.messages ?? []).filter((id) => !loaded.includes(id[0]))] : null,
    sources: [...new Set([...knew, ...loaded])],
    // like the app: no lesson alerts until a timetable with lessons has been seen
    lessons: d.lessons.length ? d.lessons.length : old?.lessons ?? 0,
    cancelled: d.lessons.filter(cancelled).map((o) => o.Uid),
    subst: Object.fromEntries(d.lessons.filter((o) => o.HelyettesTanarNeve).map((o) => [o.Uid, o.HelyettesTanarNeve])),
    values: Object.fromEntries(d.grades.map((g) => [g.Uid, display(g)])),
    unexcused: d.absences ? d.absences.filter((a) => a.IgazolasAllapota === 'Igazolatlan').map((a) => a.Uid) : old?.unexcused ?? null,
  }
  return { alerts: out, state }
}

/** HideRule.matches (HiddenLessons.swift): the rules the phone sends, applied the same way. */
function hidden(o, rules = []) {
  const t = new Date(o.KezdetIdopont)
  const subject = cap(o.Tantargy?.Nev ?? o.Nev ?? '')
  const slot = o.Oraszam != null ? String(o.Oraszam) : `${pad(t.getHours())}:${pad(t.getMinutes())}`
  return rules.some((r) => r.subject === subject && (
    r.kind === 'subject' ||
    (r.kind === 'once' && r.day === day(t) && r.slot === slot) ||
    (r.kind === 'weekly' && r.weekday === t.getDay() + 1 && r.slot === slot)))
}

// --- one poll, and the loop ---

/** Where a tap on the notification opens Firka (its URL scheme, AppTab in the app). */
const tabs = { test: 'home', grades: 'grades', edited: 'grades', unexcused: 'absences', cancelled: 'timetable', substituted: 'timetable', absences: 'absences', homework: 'more', tests: 'more', messages: 'more' }
export const link = (id) => tabs[id] && `firka://${tabs[id]}`

async function publish(ntfy, a) {
  const r = await fetch(ntfy.url, {
    method: 'POST', headers: { authorization: `Bearer ${ntfy.token}` },
    body: JSON.stringify({ topic: ntfy.topic, title: a.title, message: a.lines.join('\n'), click: link(a.id) }),
  })
  if (!r.ok) throw new Http(`ntfy: HTTP ${r.status}`)
}

export async function pollOnce(dir, { k = KRETA, ntfy, now = new Date() }) {
  const tokenFile = join(dir, 'token.json'), stateFile = join(dir, 'state.json')
  const s = session(tokenFile, k)
  if (!s) return 'no-login'
  const old = readJSON(stateFile, null)
  try {
    const d = await fetchAll(s, now, k)
    const { alerts, state } = changes(old, d, now, readJSON(join(dir, 'prefs.json'), {}))
    for (const g of d.grades) {
      if (old?.grades && !old.grades.includes(g.Uid)) console.log(`new grade, ${Math.round((now - new Date(g.RogzitesDatuma)) / 60e3)} min after KRÉTA recorded it`)
    }
    for (const a of alerts) await publish(ntfy, a)   // state saved after: a failed publish is retried next poll
    writeJSON(stateFile, state)
    return alerts.length ? `${alerts.length} sent` : 'ok'
  } catch (e) {
    if (!(e instanceof Reauth)) throw e
    renameSync(tokenFile, join(dir, 'token.dead.json'))   // stops polling until login.mjs writes a new one
    await publish(ntfy, { title: 'A Firka szerver kijelentkezett', lines: ['Jelentkeztesd be újra: node login.mjs a szerveren.'] })
    return 'reauth'
  }
}

/**
 * The phone's side, over the tailnet only (tailscale serve → 127.0.0.1): PUT /api/prefs, GET /api/status,
 * POST /api/test (Settings' test button: one notification through ntfy, to see the whole path works).
 * Tailscale names the sender in Tailscale-User-Login; only the owner gets in, so no password to keep.
 * GET /health is open (Uptime Kuma asks it over the Docker network) and says only ok or what is wrong.
 */
export function api(dir, owner, status, send) {
  return (req, res) => {
    const reply = (code, body) => { res.writeHead(code, body ? { 'content-type': 'application/json' } : {}); res.end(body && JSON.stringify(body)) }
    if (req.method === 'GET' && req.url === '/health') {
      const why = healthy(status, existsSync(join(dir, 'token.json')), new Date())
      res.writeHead(why ? 503 : 200, { 'content-type': 'text/plain' }); return res.end(why ?? 'ok')
    }
    if (!owner || req.headers['tailscale-user-login'] !== owner) return reply(403)
    if (req.method === 'GET' && req.url === '/api/status') return reply(200, { ...status, loggedIn: existsSync(join(dir, 'token.json')) })
    if (req.method === 'POST' && req.url === '/api/test') {
      send({ id: 'test', title: 'Firka teszt', lines: ['A szerver értesítései működnek.'] }).then(() => reply(204), (e) => { console.error(String(e)); reply(502) })
      return
    }
    if (req.method !== 'PUT' || req.url !== '/api/prefs') return reply(404)
    let body = ''
    req.on('data', (c) => { body += c; if (body.length > 1e6) req.destroy() })
    req.on('end', () => {
      let p
      try { p = JSON.parse(body) } catch { return reply(400) }
      if (!p || typeof p !== 'object' || Array.isArray(p)) return reply(400)
      writeJSON(join(dir, 'prefs.json'), p)
      reply(204)
    })
  }
}

/** null when all is well; otherwise why. An hour without a good poll covers a night interval and a back-off. */
export function healthy(status, loggedIn, now) {
  if (!loggedIn) return 'not signed in to KRÉTA (node login.mjs)'
  if (now - new Date(status.lastOk) > 60 * 60e3) return `no good poll since ${status.lastOk}`
  return null
}

export const interval = (now) => { const h = now.getHours(); return (h >= 6 && h < 22 ? 5 : 30) * 60e3 }

if (import.meta.url === `file://${process.argv[1]}`) {
  const dir = process.env.DATA_DIR ?? '/data'
  const status = { lastOk: new Date().toISOString() }   // a fresh start counts as good until the first hour runs out
  const ntfy = () => ({ url: process.env.NTFY_URL, topic: process.env.NTFY_TOPIC, token: readFileSync(join(dir, 'publish-token'), 'utf8').trim() })
  createServer(api(dir, process.env.OWNER_LOGIN, status, (a) => publish(ntfy(), a))).listen(Number(process.env.PORT ?? 8087))
  for (;;) {
    let wait
    try {
      const r = await pollOnce(dir, { ntfy: ntfy() })
      Object.assign(status, { lastPoll: new Date().toISOString(), result: r })
      if (r !== 'no-login' && r !== 'reauth') status.lastOk = status.lastPoll
      if (r !== 'no-login') console.log(status.lastPoll, r)
      wait = r === 'no-login' ? 60e3 : interval(new Date())
    } catch (e) {
      Object.assign(status, { lastPoll: new Date().toISOString(), result: String(e) })
      console.error(status.lastPoll, String(e))
      wait = 15 * 60e3   // KRÉTA or ntfy unwell: back off
    }
    await new Promise((ok) => setTimeout(ok, wait))
  }
}
