# Notifications from the server (ntfy)

Status: steps 1–4 built and running (26 Nov 2026). Addresses, topic and logins live in the server's .env, not here.

## Why

Firka notices a new grade only when iOS runs its `BGAppRefresh` task. The app already asks for the 15 minutes
minimum (`Background.schedule`, Store.swift:480), but iOS decides when it really runs. In practice that is
30 minutes to several hours, and it never runs while the app is swiped away or the phone is in Low Power Mode.
On 26 Nov 2026 the "Irodalom: új jegy" notification arrived more than an hour late.

The app cannot receive push itself. The free developer account (the 7-day build) has no Push Notifications
capability. ntfy gets around that: its iOS app *has* push, and a server of ours can publish to it.

## Target

- A new grade, cancelled lesson, substitution, homework, test, absence or message reaches the phone
  **within 5 minutes** during the day (06:00–22:00, Budapest) and within 30 minutes at night.
- Measurable: the server logs `now − rogzitesDatuma` for every new grade (the record time KRÉTA gives).

## Shape

```
home server (Docker)                                 iPhone
┌────────────────────────────┐                 ┌──────────────────────┐
│ firka-push (node:http)     │ every 5 min     │ Firka                │
│  KRÉTA poll → diff → ntfy  │──── KRÉTA ────▶ │  Settings › Szerver  │
│  data/: token, last state  │                 │  értesítések: sends  │
├────────────────────────────┤ publish         │  sends prefs         │
│ ntfy (self-hosted)         │◀───────────     ├──────────────────────┤
│  upstream: ntfy.sh         │── APNs wake ──▶ │ ntfy app             │
└────────────────────────────┘ (via ntfy.sh)   │  fetches the message │
                                               │  over Tailscale      │
                                               └──────────────────────┘
```

### 1. The token: a login of its own

KRÉTA's IdP rotates refresh tokens: each refresh returns a new one and the old one stops working. If the
phone and the server shared one login, whichever refreshed second would be signed out. So the server gets its
**own** session:

- Built: `server/push/login.mjs` on the server prints the IdP login address (PKCE); the owner signs in in a browser
  and pastes the address it lands on (`…/oauthredirect?code=…`). The token never touches the phone or the Mac.
- An in-app pairing screen was planned; it was not needed. If KRÉTA refuses the session, the server sends one
  "A Firka szerver kijelentkezett" notification and waits for the next `login.mjs`.
- The phone's settings reach the server through `tailscale serve`, which names the sender
  (`Tailscale-User-Login`): only the owner's login (`OWNER_LOGIN` in `.env`) gets in, so there is no secret to keep.

### 2. The server: `server/` in this repo

- `server/push/poll.mjs` on `node:http`, no dependencies, in Docker, bound to 127.0.0.1.
- What a poll asks KRÉTA for: `Ertekelesek`, this week's and next week's timetable, `HaziFeladatok`,
  `BejelentettSzamonkeresek`, `Mulasztasok`, and the inbox. That is 7 requests, fewer than one app
  refresh, which also asks for `TanuloAdatlap`, notices and class averages. At 5 minutes from 06 to 22
  and 30 minutes at night, that comes to about 1 400 requests a day.
- Diff: a port of `Notifier.changes` (Store.swift:401). It works on ID sets, so the JS is about 60 lines. It
  keeps the same guards: no first-sync flood, and an empty list followed by a full one is a new baseline.
  Last state goes to `data/state.json`, written temp-then-rename.
- Refresh: `/connect/token` with `grant_type=refresh_token` when the access token is within 60 s of expiry.
  The new refresh token is saved before anything else, otherwise a crash would lose the session.
- On `reauth` (400/401 from the IdP), publish one "A szerver kijelentkezett, párosítsd újra" and stop
  polling until the next `login.mjs`.
- Prefs from the phone: the enabled kinds (`Notifier.kinds`), surprise grades (no value in the text),
  hidden lessons, renamed subjects and teachers. The app sends them `PUT /api/prefs` after each change
  when it is in the foreground.

### 3. ntfy

- A self-hosted `binwiederhier/ntfy` container with `upstream-base-url: https://ntfy.sh`. Without it, the iOS
  app gets no instant delivery from a self-hosted server. ntfy.sh sees only a poll request (the message id
  and a hash of the topic), not the grade.
- It needs a new Tailscale HTTPS port. In use already: 443 (Kuma), 8080, 8081, 8443, 10000.
  Taken: `:8444` → 8085 by another app. Used: **`:8445` → local 8086** (topic `firka-<random>`). Check `tailscale serve status` first. Setting it up needs the sudo
  password, so the owner runs it.
- The topic is long and random, with an access token on ntfy and anonymous access off.
- Click action: `X-Click: firka://grades` (or `…/timetable`, `…/messages`). Firka registers the `firka`
  URL scheme and opens that tab.

### 4. Firka changes

- Settings: a new "Értesítések a szerverről" section: a toggle, the server status (last
  poll, last error from `GET /api/status`), and a test button that sends one ntfy message.
- When it is on, `Notifier.post` does not send local notifications, or every change would arrive twice. The
  background refresh still runs for the widget and the Live Activity.
- `firka://` URL scheme → `onOpenURL` → tab switch.

## Risks

- **The refresh token on the server is a full KRÉTA session**: grades, messages, everything the app can
  read. It sits in `data/token.json` (0600, root-owned container volume), reachable only over the tailnet.
  Deleting `data/token.json` on the server ends it. Changing the KRÉTA password probably ends the session too; this is not verified.
- **KRÉTA might rate-limit or flag** 1 400 requests/day from one IP. The poll backs off to 15 minutes after an
  HTTP 429/5xx, and the server logs it.
- **The ntfy app must reach the server when the push arrives.** If Tailscale on the iPhone is off at that
  moment, ntfy shows a placeholder ("New message") instead of the text. Tailscale's on-demand setting fixes it.
- Tapping a notification opens the ntfy app, unless the click action is set (point 3).

## Tests (TDD, as CLAUDE.md asks)

- Server: `node --test`. Cases:
  - the diff on recorded fixtures: new grade, cancelled lesson, first sync, empty-then-full;
  - the token rotation: the new refresh token is saved before the poll;
  - reauth stops the polling;
  - a fake KRÉTA and a fake ntfy on `node:http` check that the right requests are made.
- App:
  - the settings upload and the status against `FirkaTests/Stub.swift` (host `push.test`);
  - `Notifier.toPost` is silent when the server is on;
  - the URL scheme maps to the right tab (pure function, `ScreenLogic`).
- One UI test for the Settings section (demo mode).

## Steps

1. ntfy container + Tailscale port; the owner installs the ntfy app and subscribes. Check: `curl` publishes a
   test message and it shows on the lock screen within seconds.
2. `server/`: poll + diff + publish, tested (`node --test server/push`). Done 2026-11-26. The server signs in with
   `server/push/login.mjs` (its own session, the owner signs in in a browser and pastes the redirect address):
   the phone's token cannot be copied, refresh tokens are single-use.
3. Done 2026-11-26: Settings › „Értesítések a szerverről”; when on, the phone's own notifications stay off and its
   settings (kinds, surprise grades, renames, hidden lessons) go to `PUT /api/prefs`.
4. Done 2026-11-26: `firka://<tab>` (AppTab); a tap opens ntfy for a moment, then Firka on that tab.
5. One week live: compare the `rogzitesDatuma` delays with what the background refresh gave.

## Open questions for the owner

1. ~~Port~~: `:8445` (8444 was taken).
2. Poll every 5 minutes in the day and 30 at night: is that right, or should it be quieter?
3. ~~Fallback~~: Firka's own notifications go off while the server sends them (no duplicates).
