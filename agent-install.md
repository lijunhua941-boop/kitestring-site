# Install Kitestring for Mac — instructions for a coding agent

You are a coding agent (Claude Code, Codex or similar) running in a terminal **on the Mac that
should be reachable from the iPhone**. Follow these steps in order. Run the commands exactly as
written unless a step says otherwise. Report progress to the user in **their language** after
every numbered step, in one or two sentences. Never read, print or copy any file that could hold a
key or token (`~/.ssh/*`, `~/.local/state/vibeterm/*`, `~/Library/Keychains/*`, anything named
`*.key`, `*.pem`, `*.p8`).

**The user's language.** The helper words what it prints in Chinese, English or Spanish. The
commands below whose text reaches the user start with `VIBETERM_LANG="$lang"`: put `lang=<code>;`
at the start of each such command (shell variables may not survive between your commands), where
`<code>` is the user's language — `zh-Hans`, `en` or `es` (anything else: `en`). Then what you pass
on (the `problem` of `status`, an install error, a doctor `message`, the pairing window) is
already in their language. Only the wording changes: JSON keys, `state`, `problem_code`, check
`id`s and `status` values are the same in every language, so decide by those, never by wording.

What gets installed, and nothing else:

- `/Applications/Kitestring.app` — the menu bar app (free, signed, notarized when the
  release says so). It carries the helper `vibe-host` and its own `tmux`.
- `~/.local/share/vibeterm/` — the helper, tmux, a tmux config and shell files, written by the
  app's own installer; `~/.local/bin/vibeterm` — the command-line entry.
- `~/.local/state/vibeterm/` — session state.

The app is installed in `/Applications`. The helper and its session data are installed in the
locations listed above. No `sudo` is needed, and no system or network settings are changed.

Things only the user can do (macOS and the iPhone ask the person, not you). Tell them **when**
each one comes up; do not try to do them yourself and never work around a permission dialog:

1. Install **Tailscale** on this Mac and sign in with the same account as on the iPhone.
2. Turn on **Remote Login** (System Settings › General › Sharing). Only the current user needs
   access.
3. Approve macOS permission dialogs that name Kitestring (Local Network, Documents /
   Desktop / Downloads folders, "open an app downloaded from the Internet", login item).
4. Get the iPhone ready (below) and scan the pairing QR code with the Kitestring iPhone app.

**Tell the user this first, before you run anything**, so the phone is ready by the time you
reach pairing (the pairing code only lasts 10 minutes). They can do it while you work:

- On the iPhone, install **Tailscale** from the App Store and sign in with the same account they
  use (or will use) on this Mac.
- On the iPhone, install **Kitestring** from the App Store: https://apps.apple.com/app/kitestring-remote/id6832438353
- Open it. Connecting to your own Mac needs **Kitestring Pro** (a yearly subscription or a
  one-time purchase; the app shows the price, and its demo is free). If the app opens on the
  Kitestring Pro screen, buy or restore there now; otherwise it asks when they tap
  "Scan to Pair". Kitestring for Mac itself is free.

Do not wait for them: go on with step 0 and ask whether the phone is ready when you reach step 5.

The current release is described at `https://lijunhua941-boop.github.io/kitestring-site/download/latest.json` (version, DMG
URL, size, SHA-256).

## 0. Preflight (read-only)

```sh
sw_vers -productVersion          # must be 14.0 or later
uname -m                         # arm64 or x86_64 (the app is universal)
command -v brew || echo "no homebrew"
test -d "/Applications/Kitestring.app" && echo "app already present"
test -x "$HOME/.local/bin/vibeterm" && VIBETERM_LANG="$lang" "$HOME/.local/share/vibeterm/bin/vibe-host" status
```

- macOS older than 14.0: stop and tell the user; the app does not run there.
- `vibe-host status` printing `"state":"managed"`: an earlier installation exists. Continue; the
  steps below update it in place and keep the pairing, sessions and settings.
- `"state":"foreign"`: files that are not ours are in the way. Stop, show the user the `problem`
  text (it is in their language), and do not delete anything.

## 1. Install the app

Download the installer script and run it. It downloads the DMG in several parts at once (several
times faster than one connection on a slow or distant link), checks the published SHA-256, then
macOS's own verdict on the DMG and the app (signature, identifier `sh.kitestring.mac`,
notarization), and only then puts the app in `/Applications`. An app already there is replaced as
a whole and only if it is ours; anything else with that name is left alone and reported.

```sh
curl -fsSL --retry 3 https://lijunhua941-boop.github.io/kitestring-site/install.sh -o "${TMPDIR:-/tmp}/kitestring-install.sh" && bash "${TMPDIR:-/tmp}/kitestring-install.sh" --no-open
```

- It prints progress every 10 seconds. On a slow connection the download can take several
  minutes: give the command the longest timeout your tool allows (10 minutes if you can).
- **If the command is cut off or fails during the download, run the same command again.** It
  continues from what is already downloaded; nothing is fetched twice.
- Exit status 0 means the app is in place (the last line names its path and version, in the
  Mac's language). Exit status 1 means it stopped: the last line says why. Show it to the user
  and stop, except for an unfinished download, which you retry up to three times.
- It needs no `sudo`. On an account that cannot write to `/Applications` it opens the disk image
  and says so: ask the user to drag Kitestring to Applications, then continue.

The user may prefer Homebrew (one connection, so slower on a poor link; keeps the app updatable
with `brew upgrade`). Use it only if they ask for it:

```sh
brew install --cask lijunhua941-boop/kitestring/kitestring
```

**Then verify before running anything from the bundle** (read-only; the installer has already
checked the same things, this is your own confirmation, and it is required after the Homebrew path):

```sh
app="/Applications/Kitestring.app"
codesign --verify --deep --strict "$app" && echo "signature intact"
codesign -dv "$app" 2>&1 | grep -E '^Identifier=sh.kitestring.mac$' && echo "identifier ok"
spctl -a -t exec -vv "$app"; echo "spctl exit $?"
```

All three must pass: the signature verifies, the identifier is `sh.kitestring.mac`, and
`spctl` exits 0 with `source=Notarized Developer ID`. **If any of them fails, stop here: do not run
step 2 or anything else from the bundle.** Tell the user what failed. An `spctl` rejection on an
intact, correctly identified bundle means a pre-release build that is not notarized; only the
user can decide to open it (right-click › Open, or System Settings › Privacy & Security › Open
Anyway), and only after they have done so and told you to go on do you continue. **Never remove
the quarantine attribute yourself** (`xattr -d`), never disable Gatekeeper, and never
continue past a failed signature or identifier check.

## 2. Install the helper from the app bundle

This writes the helper, tmux and the shell files into `~/.local/share/vibeterm/` and links
`~/.local/bin/vibeterm`. It is the same code the app runs when the user clicks "Install Helper",
so the app's Setup Assistant will show that step as done.

```sh
VIBETERM_LANG="$lang" "/Applications/Kitestring.app/Contents/Helpers/vibe-host" install --from-bundle "/Applications/Kitestring.app"
VIBETERM_LANG="$lang" "$HOME/.local/share/vibeterm/bin/vibe-host" status
```

`status` must print `"state":"managed"`. Exit code 1 with a message means it refused (for example
files it does not own are in the way): show the message to the user and stop.

If `~/.local/bin` is not on the user's `PATH`, say so once; the commands below use full paths, so
nothing else depends on it.

## 3. Start the app (it starts the session service)

The session service must be started by a process in the user's login session (keychain and
privacy permissions belong to it), so start the app rather than running the service yourself:

```sh
open -a "Kitestring"
sleep 5
echo '{"v":1,"op":"hello"}' | "$HOME/.local/bin/vibeterm" rpc | plutil -extract result.server.running raw -o - -
```

Expected: `true`. The app's menu bar icon appears and its Setup Assistant window
opens; that window is for the user and shows the same steps as this document with check marks.
If the user is asked to move the app to Applications, it was not installed there: go back to
step 1.

If the service is not running after 15 s, tell the user to click the menu bar icon › Start
Service, and continue.

## 4. Check everything (machine-readable)

```sh
VIBETERM_LANG="$lang" "$HOME/.local/bin/vibeterm" doctor --json
```

Exit code 0 means no check failed. Read `checks[]`: each has `id`, `status` (`ok`, `warn`,
`fail`, `info`) and a `message` in the user's language (English when `VIBETERM_LANG` is not set,
whatever the shell's locale). Decide by `id` and `status` only. What to do per `id`:

| id | status | what to do |
|---|---|---|
| `tailscale` | `ready` is not `true` | The check's `status` is `info` even when healthy: read its boolean `ready` field (true = signed in, running and online). Not ready → user step 1. You may run `brew install --cask tailscale && open -a Tailscale` if Homebrew is present; signing in is the user's. Re-run doctor afterwards. |
| `remote_login` | fail/warn | User step 2. Open the pane for them: `open "x-apple.systempreferences:com.apple.Sharing-Settings.extension"`. Re-run doctor afterwards. |
| `claude` / `codex` | warn | Neither Claude Code nor Codex is visible to the login shell. At least one is needed; point the user to the official install instructions. Signing in to them can be done later from the iPhone. |
| `claude_hooks` | warn | The app adds its hooks when a Claude session is first created; nothing to do now. |
| `login_item` | warn/info | Optional: the user can turn on "Open at Login" in the app's menu. |
| `tcc_probe` | warn | The folder permissions are asked for when the iPhone first browses files; nothing to do now. |
| `slow_rpc` | info | A log of slow requests exists; informational. |
| anything else | fail | Show the user its `message` as it is (already in their language) and stop before pairing. |

Repeat the doctor until `tailscale` has `"ready": true` and `remote_login` is `ok`. Do not loop
faster than every 10 seconds and stop after 10 minutes with a summary of what is still missing.

## 5. Pair the iPhone

Only when `tailscale` is ready, `remote_login` is `ok` and the service is running. The pairing code is
a one-time secret valid for 10 minutes; it is shown on **this Mac's screen** (a QR code opened in
Preview) and must not be copied into the conversation, a file or a log.

**First ask the user whether the iPhone is ready, and wait for the answer** (do not start the
code before; the 10 minutes would run out while they install or pay):

- Kitestring is installed from the App Store (https://apps.apple.com/app/kitestring-remote/id6832438353) and, if it showed
  the Kitestring Pro screen, the purchase is done or restored;
- Tailscale on the iPhone is connected, with the same account as this Mac.

Also tell them: while your QR code is open, **do not click "Pair iPhone…" in the Mac's menu bar or
the pairing step of the Setup Assistant**. Only one pairing can be open at a time; the QR code to
scan is the one in Preview.

Record the devices that are already paired (an upgrade or a second iPhone starts with a non-empty
list), then run the pairing in the background (it blocks until the phone redeems the code, or 10
minutes). Its standard output draws the QR code and is discarded; its error output holds only
messages and is kept:

```sh
"$HOME/.local/bin/vibeterm" devices --json
VIBETERM_LANG="$lang" nohup "$HOME/.local/bin/vibeterm" pair > /dev/null 2> "${TMPDIR:-/tmp}/kitestring-pair.err" &
pair_pid=$!
```

Tell the user what to do on the iPhone, in their language:

- First Mac: open Kitestring; on the "Connect Your Mac" screen tap **Scan to Pair**
  (Chinese 「扫码配对」, Spanish «Escanear para vincular»). If the app asks for
  Kitestring Pro at this point, buy or restore, then tap it again.
- A Mac is already paired in the app: Settings › **Add Mac** (「添加 Mac」, «Añadir Mac»).
- Allow the camera, scan the QR code shown in Preview on this Mac, and confirm with **Pair**.

Then poll (every 10 s, up to 10 minutes) until the pairing process has exited, reading its exit
status; a new fingerprint in `devices` is the confirmation but not required (an iPhone that was
paired with this Mac before keeps its key, so a successful re-pairing adds no fingerprint):

```sh
if kill -0 "$pair_pid" 2>/dev/null; then echo "pairing still open"; else wait "$pair_pid"; echo "pairing exit $?"; cat "${TMPDIR:-/tmp}/kitestring-pair.err"; fi
"$HOME/.local/bin/vibeterm" devices --json
```

- `pairing exit 0`: the iPhone redeemed the code. Report the device `name` (the new
  fingerprint's, or the one the user named).
- `pairing exit 1`: the code expired or was voided (the iPhone says the code expired or was
  already used). Ask the user whether the phone is ready now, then repeat this step once.
- `pairing exit 2`: the pairing could not start; the message printed after it (already in the
  user's language) says why. "Another pairing is in progress" means the app's own pairing window
  or another terminal has a code open: ask the user to scan the code shown **there**, or to close
  that window, then repeat this step. A Tailscale or Remote Login message: go back to step 4.
- If you have to give up while it is still open, end it (`kill "$pair_pid"`), which voids the
  unused code. Several iPhones can be paired, one QR code each.

## 6. Kite Voice (only if the user asks for it)

Kite Voice is a separate iPhone app from the same developer: a voice keyboard that can use this
Mac for speech recognition and AI polish (https://apps.apple.com/app/kite-voice-ai-dictation/id6833265822). Skip this step unless the
user says they use it. Recognition on the Mac needs "Local Dictation", which only the user can
turn on (macOS asks them to approve a login item):

```sh
uname -m                                                   # must be arm64 (Apple silicon)
df -g "$HOME" | awk 'NR==2 { print $4 " GB free" }'        # about 6 GB free is needed
```

- Not `arm64`: Local Dictation does not run on this Mac; Kite Voice then uses the iPhone's own
  speech recognition. Say so and skip the rest of this step.
- Otherwise tell the user: menu bar Kitestring icon › **Local Dictation…**
  (「本机听写…」, «Dictado local…») › **Turn On Local Dictation** (「打开本机听写」, «Activar
  dictado local»). It downloads about 3.8 GB of recognition models and can take a while; the
  window shows the progress and says when Local Dictation is on.
- AI polish uses Claude Code signed in on this Mac; without it Kite Voice still gets the
  recognised text.
- Pairing Kite Voice is step 5 again with its own code (one QR code per app): in Kite Voice, tap
  "配对 Mac" and scan. Kite Voice 1.0.0 cannot read this Mac's code; it needs **Kite Voice 1.0.1
  or later** (update it in the App Store first).

## 7. Report

Tell the user, in their language:

- The app version installed (`defaults read "/Applications/Kitestring.app/Contents/Info.plist" CFBundleShortVersionString`) and the helper version (`"$HOME/.local/bin/vibeterm" version`).
- Which doctor checks are still `warn`, in plain words, and whether an iPhone is paired.
- If no iPhone is paired yet: what is left on the phone (the App Store link above, Pro, Tailscale)
  and that they can pair any time from the Mac's menu bar › "Pair iPhone…".
- How to update later: the app's own "Check for Updates" (or `brew upgrade --cask kitestring` if it
  was installed with Homebrew).
- How to uninstall: quit the app, run `VIBETERM_LANG=<code> "$HOME/.local/share/vibeterm/bin/vibe-host" uninstall`
  (removes the helper files and the iPhone's authorized key; exit 5 means the key could not be
  removed and the message says what to do), then `brew uninstall --cask kitestring` or drag the
  app to the Trash.
- Where help is: `https://lijunhua941-boop.github.io/kitestring-site/support/`, `lijunhua941@gmail.com`.

Do not run anything after the report. Do not change shell profiles, login items, firewall,
sshd or Tailscale settings, and do not delete files you did not create in this run.
