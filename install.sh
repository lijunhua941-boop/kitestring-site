#!/bin/bash
# Kitestring for Mac: download and install the current release.
#
#   curl -fsSL https://lijunhua941-boop.github.io/kitestring-site/install.sh | bash
#   curl -fsSL https://lijunhua941-boop.github.io/kitestring-site/install.sh | bash -s -- --no-open
#
# What it does, and nothing else:
#   1. reads https://lijunhua941-boop.github.io/kitestring-site/download/latest.json (version, DMG address, size, SHA-256);
#   2. downloads the DMG in several parts at once; an interrupted download continues where it
#      stopped the next time this is run (parts are kept in the temporary folder);
#   3. checks the SHA-256, then macOS's own verdict on the DMG and on the App (signature,
#      identifier sh.kitestring.mac, notarization). Anything that fails stops here;
#   4. puts Kitestring.app in /Applications (an older copy of ours is replaced as a whole,
#      anything else with that name is left alone), and opens it.
# No sudo, no settings changed, nothing else written. The App's Setup Assistant does the rest.
#
# Options: --no-open   install only; do not open the App (an App that was running is restarted)
#          --parts N   connections used for the download (default 8, 1 = one stream)
# Exit status: 0 installed; 1 stopped, with the reason on the last line.
set -u

main() {
  local site="https://lijunhua941-boop.github.io/kitestring-site" name="Kitestring" bundle_id="sh.kitestring.mac"
  local dest="${KITESTRING_INSTALL_DIR:-/Applications}"   # another folder only for testing this script
  local parts=8 open_app=1

  # Messages in the Mac's language (Chinese, Spanish, otherwise English).
  local L=en first
  first=$(defaults read -g AppleLanguages 2>/dev/null | sed -n '2s/[^A-Za-z-]//gp')
  case "$first" in zh*) L=zh ;; es*) L=es ;; esac
  say() { case "$L" in zh) printf '%s\n' "$1" ;; es) printf '%s\n' "$3" ;; *) printf '%s\n' "$2" ;; esac; }
  die() { say "$@" >&2; exit 1; }

  while [ $# -gt 0 ]; do
    case "$1" in
      --no-open) open_app=0; shift ;;
      --parts) [ $# -ge 2 ] || die "--parts 后面要跟一个数字" "--parts needs a number" "--parts necesita un número"
               parts=$2; shift 2 ;;
      -h|--help) sed -n '2,19p' "$0" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0 ;;
      *) die "不认识的参数：$1" "Unknown option: $1" "Opción desconocida: $1" ;;
    esac
  done
  case "$parts" in ''|*[!0-9]*) parts=8 ;; esac
  [ "$parts" -ge 1 ] && [ "$parts" -le 16 ] || parts=8

  [ "$(uname -s)" = Darwin ] || die "这个脚本只能在 Mac 上运行。" "This script runs on a Mac only." "Este script solo funciona en un Mac."

  # 1. The release.
  local work meta
  work=$(mktemp -d) || die "无法创建临时文件夹。" "Could not create a temporary folder." "No se pudo crear una carpeta temporal."
  trap "rm -rf '$work'" EXIT
  meta="$work/latest.json"
  curl -fsSL --retry 5 --retry-delay 2 --connect-timeout 20 "$site/download/latest.json" -o "$meta" </dev/null \
    || die "读不到版本信息（$site/download/latest.json）。请检查网络后重试。" \
           "Could not read the release information ($site/download/latest.json). Check the network and try again." \
           "No se pudo leer la información de la versión ($site/download/latest.json). Revisa la red e inténtalo de nuevo."
  field() { plutil -extract "$1" raw -o - "$meta" 2>/dev/null; }
  local url sha size version build min_macos
  url=$(field dmg_url); sha=$(field dmg_sha256); size=$(field dmg_bytes)
  version=$(field version); build=$(field build); min_macos=$(field min_macos)
  case "$url" in https://*) ;; *) url="" ;; esac
  case "$size" in ''|*[!0-9]*) size="" ;; esac
  printf '%s' "$sha" | grep -Eq '^[0-9a-f]{64}$' || sha=""
  [ -n "$url" ] && [ -n "$sha" ] && [ -n "$size" ] && [ -n "$version" ] && [ -n "$build" ] \
    || die "版本信息不完整，已停止。" "The release information is incomplete. Stopped." "La información de la versión está incompleta. Detenido."

  local os_major min_major
  os_major=$(sw_vers -productVersion | cut -d. -f1); min_major=$(printf '%s' "${min_macos:-14}" | cut -d. -f1)
  [ "$os_major" -ge "$min_major" ] 2>/dev/null \
    || die "$name for Mac 需要 macOS ${min_macos:-14} 或更高，这台 Mac 是 $(sw_vers -productVersion)。" \
           "$name for Mac needs macOS ${min_macos:-14} or later; this Mac has $(sw_vers -productVersion)." \
           "$name para Mac necesita macOS ${min_macos:-14} o posterior; este Mac tiene $(sw_vers -productVersion)."

  # 2. The download: kept between runs, so an interrupted one continues.
  local cache dmg
  cache="${TMPDIR:-/tmp}"; cache="${cache%/}/kitestring-install-$version-$build"
  mkdir -p "$cache" || die "无法创建 ${cache}。" "Could not create $cache." "No se pudo crear $cache."
  dmg="$cache/$name.dmg"
  mb() { awk -v b="$1" 'BEGIN { printf "%.1f", b / 1000000 }'; }
  sha_ok() { [ -f "$dmg" ] && [ "$(shasum -a 256 "$dmg" 2>/dev/null | cut -d' ' -f1)" = "$sha" ]; }
  bytes() { stat -f %z "$1" 2>/dev/null || echo 0; }

  if sha_ok; then
    say "已有下载好的 $name ${version}（校验通过）。" "$name $version is already downloaded (checksum OK)." "$name $version ya está descargado (suma correcta)."
  else
    rm -f "$dmg"
    say "正在下载 $name for Mac ${version}（$(mb "$size") MB）…" "Downloading $name for Mac $version ($(mb "$size") MB)…" "Descargando $name para Mac $version ($(mb "$size") MB)…"
    # Parts need a server that answers ranges; otherwise one stream, still resumable.
    local ranged
    ranged=$(curl -sL --connect-timeout 20 -r 0-0 -o /dev/null -w '%{http_code}' "$url" </dev/null)
    [ "$ranged" = 206 ] || parts=1
    [ "$size" -lt 4000000 ] && parts=1
    local step=$(( (size + parts - 1) / parts )) other
    # Parts of another layout (a run with a different --parts) do not fit this one.
    for other in "$dmg".*part*; do
      case "$other" in "$dmg.$parts.part"*) ;; *) rm -f "$other" ;; esac
    done
    # One run at a time writes the parts: downloads left behind by a run that was killed are ended
    # (found by their user agent), and their loops stop when they see another run's token.
    local agent="kitestring-install-run-$version-$build" token="$$-$RANDOM"
    printf '%s' "$token" > "$cache/run"
    pkill -f "$agent" 2>/dev/null; sleep 1; pkill -f "$agent" 2>/dev/null
    trap ': > "$cache/run"; pkill -f "$agent" 2>/dev/null; exit 130' INT TERM HUP
    fetch_part() {   # $1 = index. Appends to what is on disk; tries again after a stall or an error.
      local i=$1 from to f have want try
      from=$(( i * step )); to=$(( from + step - 1 )); [ "$to" -ge "$size" ] && to=$(( size - 1 ))
      want=$(( to - from + 1 )); f="$dmg.$parts.part$i"
      for try in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
        [ "$(cat "$cache/run" 2>/dev/null)" = "$token" ] || return 1
        have=$(bytes "$f")
        [ "$have" -gt "$want" ] && { rm -f "$f"; have=0; }
        [ "$have" -eq "$want" ] && return 0
        if [ "$ranged" = 206 ]; then
          curl -fsSL -A "$agent" --connect-timeout 20 --speed-limit 512 --speed-time 40 -r "$(( from + have ))-$to" "$url" >> "$f" </dev/null 2>/dev/null || sleep 3
        else
          curl -fsSL -A "$agent" --connect-timeout 20 --speed-limit 512 --speed-time 40 "$url" -o "$f" </dev/null 2>/dev/null || sleep 3
        fi
      done
      [ "$(bytes "$f")" -eq "$want" ]
    }
    local i pids="" monitor failed=0
    i=0; while [ "$i" -lt "$parts" ]; do fetch_part "$i" 2>/dev/null & pids="$pids $!"; i=$(( i + 1 )); done
    ( last=-1
      while sleep 10; do
        got=0; i=0
        while [ "$i" -lt "$parts" ]; do got=$(( got + $(bytes "$dmg.$parts.part$i") )); i=$(( i + 1 )); done
        [ "$got" -ne "$last" ] && printf '  %s / %s MB (%d%%)\n' "$(mb "$got")" "$(mb "$size")" $(( got * 100 / size ))
        last=$got
      done ) 2>/dev/null &
    monitor=$!
    for i in $pids; do wait "$i" || failed=1; done
    pkill -P "$monitor" 2>/dev/null; kill "$monitor" 2>/dev/null; wait "$monitor" 2>/dev/null
    trap - INT TERM HUP
    [ "$failed" -eq 0 ] \
      || die "下载没有完成。已下载的部分保留着，重新运行同一条命令会接着下载。" \
             "The download did not finish. What was downloaded is kept: run the same command again to continue." \
             "La descarga no terminó. Lo descargado se conserva: ejecuta el mismo comando otra vez para continuar."
    : > "$dmg"
    i=0; while [ "$i" -lt "$parts" ]; do cat "$dmg.$parts.part$i" >> "$dmg"; i=$(( i + 1 )); done
    if ! sha_ok; then
      rm -f "$dmg" "$dmg".*part*
      die "下载的文件校验不符（SHA-256），已删除。请重新运行。" \
          "The downloaded file does not match its SHA-256 and was removed. Run the command again." \
          "El archivo descargado no coincide con su SHA-256 y se eliminó. Ejecuta el comando otra vez."
    fi
    rm -f "$dmg".*part*
    say "下载完成，SHA-256 校验通过。" "Downloaded; SHA-256 checksum OK." "Descargado; suma SHA-256 correcta."
  fi

  # 3. macOS's verdict on the DMG, then on the App inside it.
  spctl -a -t open --context context:primary-signature "$dmg" >/dev/null 2>&1 \
    || die "磁盘映像没有通过 macOS 的签名与公证检查，已停止，没有安装任何东西。" \
           "The disk image did not pass macOS's signature and notarization check. Stopped; nothing was installed." \
           "La imagen de disco no pasó la comprobación de firma y notarización de macOS. Detenido; no se instaló nada."

  local app="$dest/$name.app" stage="$dest/$name.app.new" backup="$dest/$name.app.previous" mnt="$work/vol"
  ident() { codesign -dv "$1" 2>&1 | sed -n 's/^Identifier=//p'; }
  ours() { [ "$(ident "$1")" = "$bundle_id" ]; }
  if [ ! -w "$dest" ]; then
    open "$dmg" 2>/dev/null
    die "这个账户不能写入「应用程序」文件夹。磁盘映像已打开：请把 $name 拖进「应用程序」。" \
        "This account cannot write to the Applications folder. The disk image is open: drag $name to Applications." \
        "Esta cuenta no puede escribir en la carpeta Aplicaciones. La imagen de disco está abierta: arrastra $name a Aplicaciones."
  fi
  # What an interrupted earlier run of this script may have left: only ever ours.
  if [ -e "$stage" ]; then ours "$stage" && rm -rf "$stage"; fi
  if [ -e "$backup" ] && ours "$backup"; then
    if [ -e "$app" ]; then rm -rf "$backup"; else mv "$backup" "$app"; fi
  fi
  if [ -e "$stage" ] || [ -e "$backup" ]; then
    die "$stage 或 $backup 挡在那里，而且不是 $name 的文件。请先看看它是什么，再重新运行。" \
        "$stage or $backup is in the way and is not $name's. Look at what it is, then run this again." \
        "$stage o $backup estorba y no es de $name. Mira qué es y vuelve a ejecutar esto."
  fi
  if [ -e "$app" ] && ! ours "$app"; then
    die "$app 是另一个 App（不是 ${bundle_id}），没有动它。" \
        "$app is a different app (not $bundle_id). It was left alone." \
        "$app es otra app (no es $bundle_id). No se ha tocado."
  fi

  # Runs when the script ends, after main's variables are gone: the paths are written into it now.
  trap "[ -d '$mnt' ] && hdiutil detach -quiet '$mnt' >/dev/null 2>&1; rm -rf '$stage' '$work'" EXIT
  hdiutil attach -nobrowse -readonly -noautoopen -mountpoint "$mnt" "$dmg" >/dev/null </dev/null \
    || die "打不开磁盘映像。" "Could not open the disk image." "No se pudo abrir la imagen de disco."
  ditto "$mnt/$name.app" "$stage" \
    || die "复制 App 失败。" "Copying the app failed." "No se pudo copiar la app."
  hdiutil detach -quiet "$mnt" >/dev/null 2>&1
  codesign --verify --deep --strict "$stage" >/dev/null 2>&1 && ours "$stage" && spctl -a -t exec "$stage" >/dev/null 2>&1 \
    || die "App 没有通过签名、标识或公证检查，已停止，「应用程序」里的内容没有改动。" \
           "The app did not pass the signature, identifier or notarization check. Stopped; Applications was not changed." \
           "La app no pasó la comprobación de firma, identificador o notarización. Detenido; Aplicaciones no se modificó."

  # 4. In place. A running copy is asked to quit first and started again afterwards; sessions on
  # the Mac keep running meanwhile (they do not live in the menu bar app).
  local was_running=0 n=0
  if pgrep -f "^$app/Contents/MacOS/" >/dev/null 2>&1; then
    was_running=1
    osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 </dev/null
    while pgrep -f "^$app/Contents/MacOS/" >/dev/null 2>&1 && [ "$n" -lt 20 ]; do sleep 0.5; n=$(( n + 1 )); done
  fi
  if [ -e "$app" ]; then mv "$app" "$backup" || die "无法替换 ${app}。" "Could not replace $app." "No se pudo reemplazar $app."; fi
  if mv "$stage" "$app"; then
    rm -rf "$backup"
  else
    [ -e "$backup" ] && mv "$backup" "$app"
    die "新版本没能放进去，原来的 App 已放回。" "The new app could not be put in place; the old one is back." "No se pudo colocar la nueva app; la anterior está de vuelta."
  fi
  rm -rf "$cache"
  say "已安装：${app}（${version}，构建 ${build}）" "Installed: $app ($version, build $build)" "Instalada: $app ($version, compilación $build)"
  if [ "$open_app" -eq 1 ] || [ "$was_running" -eq 1 ]; then
    open "$app" 2>/dev/null
    say "已打开 ${name}：菜单栏出现它的图标，按「设置向导」完成余下几步。iPhone 上从 App Store 安装 ${name}，然后扫码配对。" \
        "$name is open: its icon is in the menu bar; follow the Setup Assistant for the remaining steps. On the iPhone, get $name from the App Store, then scan to pair." \
        "$name está abierto: su icono está en la barra de menús; sigue el Asistente de configuración para los pasos restantes. En el iPhone, instala $name desde el App Store y escanea para vincular."
  fi
}

main "$@"
