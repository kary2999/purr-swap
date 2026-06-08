#!/bin/bash
# USDT 换汇 发布脚本 — 自举,不依赖旧 .app 残留
#
# 用法:
#   ./scripts/release.sh patch    → 0.1.0 → 0.1.1
#   ./scripts/release.sh minor    → 0.1.0 → 0.2.0
#   ./scripts/release.sh major    → 0.1.0 → 1.0.0
#   ./scripts/release.sh 1.2.3    → 直接设成 1.2.3
#   ./scripts/release.sh          → 保持当前版本重 build
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT=$(pwd)

G="\033[32m"; Y="\033[33m"; R="\033[31m"; N="\033[0m"
step(){ echo -e "\n${G}==> $*${N}"; }
die(){ echo -e "${R}[err] $*${N}"; exit 1; }

export JAVA_HOME=${JAVA_HOME:-/opt/homebrew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home}
export PATH="$JAVA_HOME/bin:$PATH"
export ANDROID_SDK_ROOT=${ANDROID_SDK_ROOT:-/opt/homebrew/share/android-commandlinetools}
export ANDROID_HOME=$ANDROID_SDK_ROOT

command -v flutter >/dev/null || die "flutter 未装: brew install --cask flutter"
[ -f pubspec.yaml ] || die "不是 Flutter 项目根"

# ========== 版本 ==========
CUR_VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '\r')
BUMP=${1:-}

bump_semver(){
  local ver=$1 kind=$2
  IFS='.' read -r MA MI PA <<< "$ver"
  case "$kind" in
    patch) PA=$((PA+1));;
    minor) MI=$((MI+1)); PA=0;;
    major) MA=$((MA+1)); MI=0; PA=0;;
  esac
  echo "$MA.$MI.$PA"
}

if [ -z "$BUMP" ]; then
  NEW_VER=$CUR_VER
  step "版本不变: $CUR_VER"
elif [[ "$BUMP" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  NEW_VER=$BUMP
  step "版本设为 $CUR_VER → $NEW_VER"
elif [[ "$BUMP" =~ ^(patch|minor|major)$ ]]; then
  NEW_VER=$(bump_semver "$CUR_VER" "$BUMP")
  step "版本 $BUMP 升级: $CUR_VER → $NEW_VER"
else
  die "version arg 错误: $BUMP"
fi
[ "$NEW_VER" != "$CUR_VER" ] && sed -i '' "s/^version: .*/version: $NEW_VER/" pubspec.yaml
VER=$NEW_VER

# 同步 lib/version.dart (app 内自更新检测要读这个常量)
cat > lib/version.dart <<DART_EOF
/// 当前 app 版本号。
/// 由 scripts/release.sh 自动 sed 写入，不要手动改。
const String kAppVersion = '$VER';
DART_EOF

# ========== Flutter builds ==========
step "Flutter build web (本地 canvaskit, 避开 gstatic CDN 跨域)"
# --no-web-resources-cdn: canvaskit.wasm 本地化, 否则 chrome --app 模式下
# CORS 注入脚本会把 https://www.gstatic.com/.../canvaskit.wasm 重写到 /proxy/,
# 但 WebAssembly.compileStreaming 对 chunked 响应不友好 → 白屏
flutter build web --release --pwa-strategy=none --base-href=/ \
  --no-web-resources-cdn 2>&1 | tail -2

# 修 index.html 标题 (Flutter web 默认从 pubspec.name 取 = currency_exchange)
sed -i '' \
  -e 's|<title>currency_exchange</title>|<title>Purr Swap · 换金所</title>|' \
  -e 's|content="currency_exchange"|content="Purr Swap · 换金所"|g' \
  -e 's|content="A new Flutter project."|content="USDT 多渠道比价 + 记账 + 风险提示"|' \
  build/web/index.html

# 注入 CORS 代理
python3 - <<'PY'
p='build/web/index.html'
t=open(p).read()
if 'CORS proxy' in t: exit()
inj = '''  <script>
  (function(){var S=location.origin;function x(u){try{return new URL(u,location.href).origin!==S;}catch(e){return false;}}
  function r(u){return '/proxy/?url='+encodeURIComponent(new URL(u,location.href).toString());}
  var oO=XMLHttpRequest.prototype.open;XMLHttpRequest.prototype.open=function(m,u){if(typeof u==='string'&&x(u))arguments[1]=r(u);return oO.apply(this,arguments);};
  var oF=window.fetch;window.fetch=function(i,n){try{var u=typeof i==='string'?i:(i&&i.url);if(u&&x(u)){var nu=r(u);i=(typeof i==='string')?nu:new Request(nu,i);}}catch(e){}return oF.call(window,i,n);};})();
  </script>
'''
open(p,'w').write(t.replace('<head>\n','<head>\n'+inj,1))
PY

step "Flutter build APK"
flutter build apk --release 2>&1 | tail -2

# ========== Go server ==========
if [ -f native/server.go ]; then
  step "Go build universal (arm64 + amd64)"
  (
    cd native
    GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o server-arm64 server.go
    GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o server-amd64 server.go
    lipo -create server-arm64 server-amd64 -output server-universal
    rm -f server-arm64 server-amd64
  )
fi

# ========== .app 从零重建 ==========
step "从零重建 .app"
APP="dist/Purr Swap.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/web"

# --- launcher (embedded) ---
cat > "$APP/Contents/MacOS/launcher" <<'LAUNCHER_EOF'
#!/bin/bash
# Purr Swap launcher — Go server + Chrome app 模式 · 单例
set -u

APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RES="$APP_DIR/Resources"
SERVER_BIN="$APP_DIR/MacOS/server"
WEB_DIR="$RES/web"
SUPPORT="$HOME/Library/Application Support/USDTExchange"
PROFILE="$SUPPORT/browser-profile"
LOCK="$SUPPORT/running.lock"
LOG="$HOME/Library/Logs/USDT换汇.log"
mkdir -p "$SUPPORT" "$PROFILE" "$(dirname "$LOG")"

log(){ echo "[$(date +%H:%M:%S)] $*" >> "$LOG"; }
log "=== start ==="

focus_if_exists() {
  osascript 2>/dev/null <<'OSA'
try
  tell application "Google Chrome"
    set foundWindow to missing value
    repeat with w in windows
      repeat with t in tabs of w
        if URL of t contains "127.0.0.1" then
          set foundWindow to w
          exit repeat
        end if
      end repeat
      if foundWindow is not missing value then exit repeat
    end repeat
    if foundWindow is not missing value then
      activate
      set index of foundWindow to 1
      return "found"
    else
      return "notfound"
    end if
  end tell
on error
  return "err"
end try
OSA
}

if pgrep -f "Google Chrome.*--app=http://127\.0\.0\.1.*USDTExchange" >/dev/null 2>&1; then
  log "existing app-mode chrome, try focus"
  res=$(focus_if_exists)
  log "osascript: $res"
  [ "$res" = "found" ] && exit 0
  log "focus failed, fresh launch"
fi

if [ -f "$LOCK" ]; then
  OLD_PID=$(head -n 1 "$LOCK" 2>/dev/null)
  if [ -z "$OLD_PID" ] || ! kill -0 "$OLD_PID" 2>/dev/null; then
    rm -f "$LOCK"
  elif ! pgrep -f "MacOS/server.*USDTExchange" >/dev/null 2>&1; then
    rm -f "$LOCK"
  fi
fi

TMP=$(mktemp -t usdt_port)
"$SERVER_BIN" "$WEB_DIR" > "$TMP" 2>> "$LOG" &
SERVER_PID=$!
log "server pid: $SERVER_PID"

cleanup() {
  log "cleanup; killing $SERVER_PID"
  kill "$SERVER_PID" 2>/dev/null
  rm -f "$TMP" "$LOCK"
}
trap cleanup EXIT INT TERM

PORT=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  sleep 0.2
  PORT=$(head -n 1 "$TMP" 2>/dev/null)
  [ -n "$PORT" ] && break
done
if [ -z "$PORT" ]; then
  osascript -e 'display alert "PurrSwap-换金所" message "本地服务启动失败,日志: ~/Library/Logs/USDT换汇.log"' >/dev/null
  exit 2
fi
URL="http://127.0.0.1:$PORT"
log "port: $PORT url: $URL"
printf "%s\n%s\n" "$SERVER_PID" "$URL" > "$LOCK"

BROWSER_APP=""
for APP_PATH in \
  "/Applications/Google Chrome.app" \
  "/Applications/Microsoft Edge.app" \
  "/Applications/Brave Browser.app" \
  "/Applications/Arc.app" \
  "/Applications/Chromium.app"; do
  [ -d "$APP_PATH" ] && { BROWSER_APP="$APP_PATH"; break; }
done

if [ -z "$BROWSER_APP" ]; then
  osascript -e 'display notification "未装 Chrome/Edge/Brave/Arc" with title "PurrSwap-换金所"' >/dev/null 2>&1
  open "$URL"
  wait "$SERVER_PID"
  exit 0
fi

log "browser: $BROWSER_APP"
find "$PROFILE" -maxdepth 1 -name "Singleton*" -delete 2>/dev/null

open -n -a "$BROWSER_APP" --args \
  --app="$URL" \
  --user-data-dir="$PROFILE" \
  --window-size=420,850 \
  --window-position=100,60 \
  --disable-extensions --disable-component-extensions-with-background-pages \
  --no-first-run --no-default-browser-check

sleep 1
APP_CHROME_PID=$(pgrep -f "Google Chrome.*--app=http://127\.0\.0\.1:$PORT" | head -1)
if [ -z "$APP_CHROME_PID" ]; then
  log "no app-mode chrome pid, fallback wait server"
  wait "$SERVER_PID"
else
  log "app chrome pid: $APP_CHROME_PID"
  while kill -0 "$APP_CHROME_PID" 2>/dev/null; do sleep 2; done
  log "chrome exited"
fi

log "=== exit ==="
LAUNCHER_EOF
chmod +x "$APP/Contents/MacOS/launcher"

# --- Go server ---
if [ -f native/server-universal ]; then
  cp native/server-universal "$APP/Contents/MacOS/server"
  chmod +x "$APP/Contents/MacOS/server"
else
  die "native/server-universal 不存在,请先 go build"
fi

# --- web 资源 ---
cp -R build/web/ "$APP/Contents/Resources/web/"

# --- Info.plist ---
cat > "$APP/Contents/Info.plist" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
    <key>CFBundleDisplayName</key><string>Purr Swap</string>
    <key>CFBundleName</key><string>Purr Swap</string>
    <key>CFBundleIdentifier</key><string>com.tope.usdtexchange</string>
    <key>CFBundleVersion</key><string>${VER}</string>
    <key>CFBundleShortVersionString</key><string>${VER}</string>
    <key>CFBundleExecutable</key><string>launcher</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleSignature</key><string>????</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>10.14</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>LSApplicationCategoryType</key><string>public.app-category.finance</string>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST_EOF

# --- 图标 ---
if [ -f assets/icon/icon.png ]; then
  ICONSET=/tmp/usdt_icon_$$.iconset
  mkdir -p "$ICONSET"
  for sz in 16 32 64 128 256 512 1024; do
    sips -z $sz $sz assets/icon/icon.png --out "$ICONSET/icon_${sz}x${sz}.png" >/dev/null 2>&1
  done
  cp "$ICONSET/icon_32x32.png"     "$ICONSET/icon_16x16@2x.png"
  cp "$ICONSET/icon_64x64.png"     "$ICONSET/icon_32x32@2x.png"
  cp "$ICONSET/icon_256x256.png"   "$ICONSET/icon_128x128@2x.png"
  cp "$ICONSET/icon_512x512.png"   "$ICONSET/icon_256x256@2x.png"
  cp "$ICONSET/icon_1024x1024.png" "$ICONSET/icon_512x512@2x.png"
  rm "$ICONSET/icon_64x64.png" "$ICONSET/icon_1024x1024.png"
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
fi

# 签名
codesign --force --deep --sign - "$APP" 2>&1 | tail -1
xattr -cr "$APP"

# ========== DMG ==========
step "打 DMG"
DMG="dist/PurrSwap-v${VER}-macOS.dmg"
find dist -maxdepth 1 -name "PurrSwap-v*-macOS.dmg*" -delete 2>/dev/null
STAGE=/tmp/usdt_dmg_$$
rm -rf "$STAGE" && mkdir "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
hdiutil create -volname "PurrSwap-换金所 v${VER}" -srcfolder "$STAGE" -ov -format UDZO "$DMG" 2>&1 | tail -1
shasum -a 256 "$DMG" > "$DMG.sha256"
rm -rf "$STAGE"

# ========== APK ==========
APK="dist/PurrSwap-v${VER}-Android.apk"
find dist -maxdepth 1 -name "PurrSwap-v*-Android.apk*" -delete 2>/dev/null
cp build/app/outputs/flutter-apk/app-release.apk "$APK"
shasum -a 256 "$APK" > "$APK.sha256"

# ========== README ==========
cat > dist/README.txt <<EOF
Purr Swap · 换金所 v${VER}
================
Built: $(date '+%Y-%m-%d %H:%M')

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📱 Android
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PurrSwap-v${VER}-Android.apk
要求: Android 7.0+

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🖥 macOS (M1-M4 + Intel)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
PurrSwap-v${VER}-macOS.dmg
要求: macOS 10.14+ · 需装 Chrome / Edge / Brave

首次提示无法验证开发者:
  右键 App → 打开,或
  sudo xattr -rd com.apple.quarantine "/Applications/Purr Swap.app"

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🎯 功能
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
⭐ 预测 · 📝 记账 · 📊 历史 · 📈 统计 · 📖 指南 · ⚙️ 设置
所有数据仅本地,卸载即清空。请定期 设置 → 导出备份。
EOF

# ========== ZIP ==========
step "打 release zip"
cd dist
ZIP="PurrSwap-v${VER}-release.zip"
find . -maxdepth 1 -name "PurrSwap-v*-release.zip*" -delete 2>/dev/null
zip -r "$ZIP" \
  "PurrSwap-v${VER}-macOS.dmg" \
  "PurrSwap-v${VER}-Android.apk" \
  "PurrSwap-v${VER}-macOS.dmg.sha256" \
  "PurrSwap-v${VER}-Android.apk.sha256" \
  "README.txt" > /dev/null
shasum -a 256 "$ZIP" > "$ZIP.sha256"
cd "$ROOT"

# ========== version.json (app 自更新检测) ==========
step "生成 dist/version.json"
APK_SHA=$(awk '{print $1}' "dist/PurrSwap-v${VER}-Android.apk.sha256")
DMG_SHA=$(awk '{print $1}' "dist/PurrSwap-v${VER}-macOS.dmg.sha256")
ZIP_SHA=$(awk '{print $1}' "dist/PurrSwap-v${VER}-release.zip.sha256")
cat > dist/version.json <<JSON_EOF
{
  "latest": "${VER}",
  "android": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${VER}-Android.apk",
  "macos": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${VER}-macOS.dmg",
  "zip": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${VER}-release.zip",
  "web": "https://kary2999.github.io/purr-swap/",
  "notes": "v${VER} (构建于 $(date '+%Y-%m-%d'))",
  "sha256": {
    "android": "${APK_SHA}",
    "macos": "${DMG_SHA}",
    "zip": "${ZIP_SHA}"
  }
}
JSON_EOF

# ========== Done ==========
step "✨ v${VER} 发布完成"
echo ""
ls -lh dist/ | grep -v "^total\|^d\|\.DS" | awk '{print "  ", $NF, "("$5")"}'
echo ""
echo "  → dist/PurrSwap-v${VER}-release.zip"
cat "dist/PurrSwap-v${VER}-release.zip.sha256"
