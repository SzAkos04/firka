// Signs the server in to KRÉTA with a session of its own (refresh tokens are single-use: sharing the phone's
// would sign one of them out). Run on the server:
//   docker compose run --rm push node login.mjs
// Open the printed address in a browser, sign in, and paste the address the browser lands on.
import { createHash, randomBytes } from 'node:crypto'
import { createInterface } from 'node:readline/promises'
import { existsSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { KRETA, tokenRequest, writeJSON } from './poll.mjs'

const redirect = 'https://mobil.e-kreta.hu/ellenorzo-student/prod/oauthredirect'
const verifier = randomBytes(32).toString('base64url')
const challenge = createHash('sha256').update(verifier).digest('base64url')
const state = randomBytes(16).toString('base64url')
const scope = 'openid email offline_access kreta-ellenorzo-webapi.public kreta-eugyintezes-webapi.public kreta-fileservice-webapi.public kreta-mobile-global-webapi.public kreta-dkt-webapi.public kreta-ier-webapi.public'
const callback = '/connect/authorize/callback?' + new URLSearchParams({
  redirect_uri: redirect, client_id: KRETA.clientId, response_type: 'code', prompt: 'login', state, nonce: state, scope,
  code_challenge: challenge, code_challenge_method: 'S256', suppressed_prompt: 'login',
}).toString().replaceAll('+', '%20')   // spaces as %20, like the app's URL
console.log('\n1. Nyisd meg böngészőben, és jelentkezz be:\n\n' + `${KRETA.idp}/Account/Login?` + new URLSearchParams({ ReturnUrl: callback }) + '\n')
console.log('2. A bejelentkezés után a böngésző egy mobil.e-kreta.hu/…oauthredirect?code=… címre ugrik (az oldal lehet üres).')
const rl = createInterface({ input: process.stdin, output: process.stdout })
const pasted = (await rl.question('   Másold ide azt a teljes címet: ')).trim()
rl.close()

const code = new URL(pasted).searchParams.get('code')
if (!code) { console.error('Nincs benne code=…, próbáld újra.'); process.exit(1) }
const g = await tokenRequest({ code, code_verifier: verifier, redirect_uri: redirect, client_id: KRETA.clientId, grant_type: 'authorization_code' })
const claims = JSON.parse(Buffer.from(g.id_token.split('.')[1], 'base64url'))
const dir = process.env.DATA_DIR ?? '/data'
writeJSON(join(dir, 'token.json'), {
  iss: claims['kreta:institute_code'], accessToken: g.access_token, refreshToken: g.refresh_token,
  expiry: Date.now() + (g.expires_in - 60) * 1000,
})
if (existsSync(join(dir, 'token.dead.json'))) rmSync(join(dir, 'token.dead.json'))
console.log(`\nKész: ${claims['kreta:user_name'] ?? ''} (${claims['kreta:institute_code']}). A lekérdező egy percen belül indul.`)
