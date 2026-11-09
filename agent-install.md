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

Four things only the user can do (macOS asks the person at the keyboard, not you). Tell them
**when** each one comes up; do not try to do them yourself and never work around a permission
dialog:

1. Install **Tailscale** on this Mac and sign in with the same account as on the iPhone.
2. Turn on **Remote Login** (System Settings › General › Sharing). Only the current user needs
   access.
3. Approve macOS permission dialogs that name Kitestring (Local Network, Documents /
   Desktop / Downloads folders, "open an app downloaded from the Internet", login item).
4. Scan the pairing QR code with the Kitestring iPhone app.

The current release is described at `https://lijunhua941-boop.github.io/kitestring-site/download/latest.json` (version, DMG
URL, SHA-256). Read it first:

```sh
curl -fsSL https://lijunhua941-boop.github.io/kitestring-site/download/latest.json
```

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

**With Homebrew** (preferred; installs or upgrades to the current release, verifies the SHA-256,
and keeps it updatable with `brew upgrade`):

```sh
brew install --cask lijunhua941-boop/kitestring/kitestring
```

**Without Homebrew** (do not install Homebrew for this; it needs an administrator password). The
DMG is checked against the published SHA-256 before anything is copied, and an app already in
`/Applications` is replaced only if it is ours (`Identifier=sh.kitestring.mac`); anything else
with that name is left alone and reported:

```sh
set -e
tmp=$(mktemp -d)
app="/Applications/Kitestring.app"
stage="$app.new"        # staged beside the destination: the final step is a rename on the same volume
backup="$app.previous"
for p in "$stage" "$backup"; do
  [ -e "$p" ] && { echo "$p is in the way (left by an earlier attempt): stop and ask the user what it is"; exit 1; }
done
trap 'rm -rf "$stage" "$tmp"' EXIT     # a failure at any step below leaves no staged copy behind
url=$(curl -fsSL https://lijunhua941-boop.github.io/kitestring-site/download/latest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["dmg_url"])')
sha=$(curl -fsSL https://lijunhua941-boop.github.io/kitestring-site/download/latest.json | python3 -c 'import json,sys; print(json.load(sys.stdin)["dmg_sha256"])')
curl -fsSL "$url" -o "$tmp/Kitestring.dmg"
echo "$sha  $tmp/Kitestring.dmg" | shasum -a 256 -c -          # must print OK; otherwise stop
if [ -e "$app" ]; then
  codesign -dv "$app" 2>&1 | grep -q '^Identifier=sh.kitestring.mac$' || { echo "another app is at $app: stop"; exit 1; }
fi
hdiutil attach -nobrowse -readonly -mountpoint "$tmp/vol" "$tmp/Kitestring.dmg"
ditto "$tmp/vol/Kitestring.app" "$stage"                          # a complete copy, nothing replaced yet
hdiutil detach "$tmp/vol"
codesign --verify --deep --strict "$stage"                                # the copy is intact; otherwise stop
codesign -dv "$stage" 2>&1 | grep -q '^Identifier=sh.kitestring.mac$' || { echo "downloaded app has another identifier: stop"; exit 1; }
# Whole-bundle replacement by rename, no merge; the old app is kept beside until the new one is in place.
if [ -e "$app" ]; then mv "$app" "$backup"; fi
if mv "$stage" "$app"; then
  rm -rf "$backup"
else
  [ -e "$backup" ] && mv "$backup" "$app"
  echo "could not place the new app: the old one is back"; exit 1
fi
```

**Then verify before running anything from the bundle** (read-only; also after the Homebrew path):

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
echo '{"v":1,"op":"hello"}' | "$HOME/.local/bin/vibeterm" rpc | python3 -c 'import json,sys; r=json.load(sys.stdin)["result"]; print("server_running", r["server"]["running"], "helper", r["helper_version"], "agents", {k: v["found"] for k, v in r["agents"].items()})'
```

Expected: `server_running True`. The app's menu bar icon appears and its Setup Assistant window
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

First record the devices that are already paired (an upgrade or a second iPhone starts with a
non-empty list), then run the pairing in the background (it blocks until the phone redeems the
code, or 10 minutes) and tell the user to open the Kitestring app on the iPhone › Settings ›
Mac › Add Mac and scan the QR code shown in Preview:

```sh
before=$("$HOME/.local/bin/vibeterm" devices --json | python3 -c 'import json,sys; print("\n".join(d["fingerprint"] for d in json.load(sys.stdin)["devices"]))')
VIBETERM_LANG="$lang" nohup "$HOME/.local/bin/vibeterm" pair > /dev/null 2>&1 &
pair_pid=$!
```

Then poll (every 10 s, up to 10 minutes) until the pairing process has exited, reading its exit
status; a new fingerprint in `devices` is the confirmation but not required (an iPhone that was
paired with this Mac before keeps its key, so a successful re-pairing adds no fingerprint):

```sh
if kill -0 "$pair_pid" 2>/dev/null; then echo "pairing still open"; else wait "$pair_pid"; echo "pairing exit $?"; fi
"$HOME/.local/bin/vibeterm" devices --json
```

`pairing exit 0` means the iPhone redeemed the code: report the device `name` (the new
fingerprint's, or the one the user named). Exit 1 means the code expired or was voided: ask the
user whether to try again, then repeat this step once. If you have to give up while it is still
open, end it (`kill "$pair_pid"`), which voids the unused code. Several iPhones can be paired, one
QR code each.

## 6. Report

Tell the user, in their language:

- The app version installed (`defaults read "/Applications/Kitestring.app/Contents/Info.plist" CFBundleShortVersionString`) and the helper version (`"$HOME/.local/bin/vibeterm" version`).
- Which doctor checks are still `warn`, in plain words, and whether an iPhone is paired.
- How to update later: `brew upgrade --cask kitestring`, or the app's own "Check for Updates".
- How to uninstall: quit the app, run `VIBETERM_LANG=<code> "$HOME/.local/share/vibeterm/bin/vibe-host" uninstall`
  (removes the helper files and the iPhone's authorized key; exit 5 means the key could not be
  removed and the message says what to do), then `brew uninstall --cask kitestring` or drag the
  app to the Trash.
- Where help is: `https://lijunhua941-boop.github.io/kitestring-site/support/`, `lijunhua941@gmail.com`.

Do not run anything after the report. Do not change shell profiles, login items, firewall,
sshd or Tailscale settings, and do not delete files you did not create in this run.
