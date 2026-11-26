// Run: node --test server/push   (the server's whole test suite; no dependencies)
process.env.TZ = 'Europe/Budapest'
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { createServer } from 'node:http'
import { mkdtempSync, readFileSync, writeFileSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { changes, pollOnce, interval, api, link } from './poll.mjs'

const now = new Date('2026-11-26T10:00:00+01:00')   // a Thursday; the week starts on Monday the 23rd
const subj = (nev) => ({ Uid: nev, Nev: nev })
const grade = (uid, nev = 'irodalom', n = 5, extra = {}) =>
  ({ Uid: uid, Tantargy: subj(nev), ErtekFajta: { Nev: 'Osztalyzat' }, SzamErtek: n, RogzitesDatuma: '2026-11-26T08:40:00Z', ...extra })
const lesson = (uid, start, extra = {}) => ({
  Uid: uid, KezdetIdopont: new Date(start).toISOString(), VegIdopont: new Date(+new Date(start) + 45 * 60e3).toISOString(),
  Tantargy: subj('matematika'), Tipus: { Nev: 'OrarendiOra' }, ...extra,
})
const data = (o = {}) => ({ grades: [], lessons: [], absences: [], homework: [], tests: [], messages: [], ...o })
const lines = (alerts) => alerts.flatMap((a) => [a.title, ...a.lines])

test('the first poll sets the baseline and sends nothing', () => {
  const { alerts, state } = changes(null, data({ grades: [grade('g1')] }), now)
  assert.deepEqual(alerts, [])
  assert.deepEqual(state.grades, ['g1'])
})

test('a new grade: the value stays hidden unless surprise grades are off, like in the app', () => {
  const { state } = changes(null, data({ grades: [grade('g1')] }), now)
  const d = data({ grades: [grade('g1'), grade('g2', 'irodalom', 4)] })
  assert.deepEqual(lines(changes(state, d, now).alerts), ['Új jegy érkezett', 'Irodalom: új jegy'])
  assert.deepEqual(lines(changes(state, d, now, { surprise: false }).alerts), ['Új jegy érkezett', 'Irodalom: 4'])
  const two = data({ grades: [grade('g1'), grade('g2'), grade('g3', 'fizika', 80, { ErtekFajta: { Nev: 'Szazalekos' } })] })
  assert.deepEqual(lines(changes(state, two, now, { surprise: false }).alerts), ['2 új jegy érkezett', 'Irodalom: 5', 'Fizika: 80%'])
  assert.deepEqual(lines(changes(state, d, now, { kinds: { notifyGrades: false } }).alerts), [])
  assert.deepEqual(lines(changes(state, d, now, { subjects: { Irodalom: 'Iroda' } }).alerts), ['Új jegy érkezett', 'Iroda: új jegy'])
})

test('an empty list and then a full one is a new baseline, not a flood', () => {
  const { state } = changes(null, data(), now)
  const d = data({ grades: ['a', 'b', 'c', 'd'].map((u) => grade(u)) })
  assert.deepEqual(changes(state, d, now).alerts, [])
})

test('cancelled and substituted lessons: only future ones, only once', () => {
  const thu12 = '2026-11-26T12:00:00+01:00', thu08 = '2026-11-26T08:00:00+01:00'
  const { state } = changes(null, data({ lessons: [lesson('l1', thu12), lesson('l2', thu08), lesson('l3', thu12)] }), now)
  const d = data({ lessons: [
    lesson('l1', thu12, { Allapot: { Nev: 'Elmaradt' } }),
    lesson('l2', thu08, { Allapot: { Nev: 'Elmaradt' } }),            // already over: no news
    lesson('l3', thu12, { HelyettesTanarNeve: 'Kiss Anna' }),
  ] })
  const r = changes(state, d, now, { teachers: { 'Kiss Anna': 'Anna néni' } })
  assert.deepEqual(lines(r.alerts), ['Elmaradt óra', 'Matematika – csütörtök 12:00', 'Helyettesítés', 'Matematika: Anna néni (csütörtök 12:00)'])
  assert.deepEqual(changes(r.state, d, now).alerts, [])
})

test('lessons the user hid in the app are not announced', () => {
  const thu12 = '2026-11-26T12:00:00+01:00'
  const three = lesson('l1', '2026-11-26T10:00:00+01:00', { Oraszam: 3 })
  const { state } = changes(null, data({ lessons: [three, lesson('l2', thu12), lesson('l3', thu12, { Tantargy: subj('fizika') })] }), now)
  const d = data({ lessons: [
    lesson('l1', '2026-11-26T10:00:00+01:00', { Oraszam: 3, Allapot: { Nev: 'Elmaradt' } }),
    lesson('l2', thu12, { Allapot: { Nev: 'Elmaradt' } }),
    lesson('l3', thu12, { Tantargy: subj('fizika'), HelyettesTanarNeve: 'Kiss Anna' }),
  ] })
  assert.equal(changes(state, d, now).alerts.length, 2)
  // HideRule as the app encodes it: weekday 1 = Sunday, slot = lesson number or start time, subject = KRÉTA's name capitalised
  const hidden = [
    { kind: 'weekly', subject: 'Matematika', weekday: 5, slot: '3' },
    { kind: 'once', subject: 'Matematika', day: '2026-11-26', slot: '12:00' },
    { kind: 'subject', subject: 'Fizika' },
  ]
  assert.deepEqual(changes(state, d, now, { hidden }).alerts, [])
  assert.equal(changes(state, d, now, { hidden: [{ kind: 'weekly', subject: 'Matematika', weekday: 4, slot: '3' }] }).alerts.length, 2)
})

test('an endpoint that failed (null) keeps what was known and announces nothing', () => {
  const abs = { Uid: 'a1', Tantargy: subj('kémia'), IgazolasAllapota: 'Igazolando', Tipus: { Nev: 'hianyzas' } }
  const { state } = changes(null, data({ absences: [abs] }), now)
  const r = changes(state, data({ absences: null }), now)
  assert.deepEqual(r.alerts, [])
  assert.deepEqual(r.state.absences, ['a1'])
  const late = { Uid: 'a2', Tantargy: subj('kémia'), IgazolasAllapota: 'Igazolt', KesesPercben: 5 }
  assert.deepEqual(lines(changes(r.state, data({ absences: [abs, late] }), now).alerts), ['Új hiányzás/késés', 'Kémia: Igazolt késés (5 perc)'])
})

test('a tap on a notification opens Firka on the tab it is about', () => {
  assert.equal(link('grades'), 'firka://grades')
  assert.equal(link('cancelled'), 'firka://timetable')
  assert.equal(link('substituted'), 'firka://timetable')
  assert.equal(link('absences'), 'firka://absences')
  for (const id of ['homework', 'tests', 'messages']) assert.equal(link(id), 'firka://more')
  assert.equal(link(undefined), undefined)
})

test('it polls every 5 minutes in the day and every 30 at night', () => {
  assert.equal(interval(new Date('2026-11-26T06:00:00+01:00')), 5 * 60e3)
  assert.equal(interval(new Date('2026-11-26T21:59:00+01:00')), 5 * 60e3)
  assert.equal(interval(new Date('2026-11-26T22:00:00+01:00')), 30 * 60e3)
  assert.equal(interval(new Date('2026-11-27T03:00:00+01:00')), 30 * 60e3)
})

// --- one poll against a fake KRÉTA and a fake ntfy ---

async function fakes({ idp = 200, first401 = false } = {}) {
  const log = [], sent = []
  let refreshed = 0, denied = false
  const kreta = createServer((req, res) => {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => {
      const url = new URL(req.url, 'http://x')
      log.push(`${req.method} ${url.pathname} ${req.headers.authorization ?? ''}`)
      const json = (s, o) => { res.writeHead(s, { 'content-type': 'application/json' }); res.end(JSON.stringify(o)) }
      if (url.pathname === '/connect/token') {
        const f = new URLSearchParams(body)
        if (idp !== 200 || f.get('refresh_token') !== `r${refreshed}`) return json(400, { error: 'invalid_grant' })
        refreshed++
        return json(200, { access_token: `a${refreshed}`, refresh_token: `r${refreshed}`, expires_in: 1800 })
      }
      if (first401 && !denied) { denied = true; return json(401, {}) }
      if (req.headers.authorization !== `Bearer a${refreshed}`) return json(401, {})
      if (url.pathname.endsWith('/Ertekelesek')) return json(200, [grade('g1'), grade('g2', 'történelem')])
      if (url.pathname.endsWith('/postaladaelemek/sajat')) return json(200, [])
      return json(200, [])
    })
  })
  const ntfy = createServer((req, res) => {
    let body = ''
    req.on('data', (c) => (body += c))
    req.on('end', () => { sent.push({ auth: req.headers.authorization, ...JSON.parse(body) }); res.end('{}') })
  })
  await Promise.all([kreta, ntfy].map((s) => new Promise((ok) => s.listen(0, '127.0.0.1', ok))))
  const base = `http://127.0.0.1:${kreta.address().port}`
  const k = { idp: base, api: () => base, inbox: base, clientId: 'c', userAgent: 'u', apiKey: 'k' }
  const close = () => { kreta.close(); ntfy.close() }
  return { k, log, sent, close, ntfy: { url: `http://127.0.0.1:${ntfy.address().port}`, topic: 't', token: 'tk' } }
}

function dir({ expired = true } = {}) {
  const d = mkdtempSync(join(tmpdir(), 'firka-push-'))
  writeFileSync(join(d, 'token.json'), JSON.stringify({ iss: 'klik1', accessToken: 'a0', refreshToken: 'r0', expiry: expired ? 0 : Date.now() + 60e3 }))
  writeFileSync(join(d, 'state.json'), JSON.stringify(changes(null, data({ grades: [grade('g1')] }), now).state))
  return d
}

test('a poll renews an expired token first, keeps the new one, and publishes what is new', async (t) => {
  const f = await fakes(); t.after(f.close)
  const d = dir()
  assert.equal(await pollOnce(d, { k: f.k, ntfy: f.ntfy, now }), '1 sent')
  assert.equal(f.log[0], 'POST /connect/token ')
  assert.ok(f.log.slice(1).every((l) => l.endsWith('Bearer a1')))
  assert.equal(JSON.parse(readFileSync(join(d, 'token.json'))).refreshToken, 'r1')
  assert.deepEqual(f.sent, [{ auth: 'Bearer tk', topic: 't', title: 'Új jegy érkezett', message: 'Történelem: új jegy', click: 'firka://grades' }])
  assert.deepEqual(JSON.parse(readFileSync(join(d, 'state.json'))).grades, ['g1', 'g2'])
  assert.equal(await pollOnce(d, { k: f.k, ntfy: f.ntfy, now }), 'ok')       // nothing new the second time
})

test('a 401 from the API renews once and retries', async (t) => {
  const f = await fakes({ first401: true }); t.after(f.close)
  assert.equal(await pollOnce(dir({ expired: false }), { k: f.k, ntfy: f.ntfy, now }), '1 sent')
})

test('a session KRÉTA refuses stops polling and says so once', async (t) => {
  const f = await fakes({ idp: 400 }); t.after(f.close)
  const d = dir()
  assert.equal(await pollOnce(d, { k: f.k, ntfy: f.ntfy, now }), 'reauth')
  assert.equal(existsSync(join(d, 'token.json')), false)
  assert.equal(f.sent.length, 1)
  assert.match(f.sent[0].title, /kijelentkezett/)
  assert.equal(await pollOnce(d, { k: f.k, ntfy: f.ntfy, now }), 'no-login')
  assert.equal(f.sent.length, 1)
})

// --- the phone's settings, over the tailnet ---

test('the phone sends its settings; only the owner, as Tailscale names them', async (t) => {
  const d = mkdtempSync(join(tmpdir(), 'firka-push-'))
  const status = { lastPoll: '2026-11-26T21:39:32.027Z', result: 'ok' }
  const srv = createServer(api(d, 'owner@example.com', status))
  await new Promise((ok) => srv.listen(0, '127.0.0.1', ok)); t.after(() => srv.close())
  const url = (p) => `http://127.0.0.1:${srv.address().port}${p}`
  const who = (login) => (login ? { 'tailscale-user-login': login } : {})
  const put = (body, login = 'owner@example.com') => fetch(url('/api/prefs'), { method: 'PUT', headers: who(login), body })
  const prefs = { kinds: { notifyGrades: false }, surprise: false, subjects: { Irodalom: 'Iroda' }, teachers: {}, hidden: [{ kind: 'subject', subject: 'Fizika' }] }

  assert.equal((await put(JSON.stringify(prefs), null)).status, 403)
  assert.equal((await put(JSON.stringify(prefs), 'someone@else.com')).status, 403)
  assert.equal((await put('{nope')).status, 400)
  assert.equal((await put('[]')).status, 400)
  assert.equal(existsSync(join(d, 'prefs.json')), false)
  assert.equal((await put(JSON.stringify(prefs))).status, 204)
  assert.deepEqual(JSON.parse(readFileSync(join(d, 'prefs.json'))), prefs)

  const st = await fetch(url('/api/status'), { headers: who('owner@example.com') })
  assert.deepEqual(await st.json(), { ...status, loggedIn: false })
  assert.equal((await fetch(url('/api/status'))).status, 403)
  assert.equal((await fetch(url('/nope'), { headers: who('owner@example.com') })).status, 404)
})
