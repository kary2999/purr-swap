#!/bin/bash
# Web (GitHub Pages) 发布脚本
#
# 用法:
#   ./scripts/release-web.sh           # build + 写入 build/web (不部署)
#   ./scripts/release-web.sh deploy    # build + 推送到 gh-pages 分支
#
# vs scripts/release.sh 区别:
#   - 不注入 /proxy/?url= 脚本（GitHub Pages 是纯静态，没有 proxy）
#   - base-href = /purr-swap/   （GitHub Pages 在子路径）
#   - 部署目标: gh-pages 分支
#
# CORS 受限说明（4/6 个 API 浏览器跨域被拦）：
#   ✓ api.wise.com/v3/comparisons        浏览器可直连（ACAO=*）
#   ✓ prod.pandaremit.com               浏览器可直连
#   ✗ wise.com/rates/live               不可（已被 api.wise.com 替代，不影响）
#   ✗ p2p.binance.com (Binance C2C)     不可，web 版会缺这条
#   ✗ www.okx.com (OKX C2C)             不可
#   ✗ usa.visa.com                      不可
# RateFetcher._safe() 已包裹每个源，单源失败不影响其他。
set -euo pipefail
cd "$(dirname "$0")/.."

G="\033[32m"; Y="\033[33m"; N="\033[0m"
step(){ echo -e "\n${G}==> $*${N}"; }

MODE=${1:-}
BASE_HREF=${BASE_HREF:-/purr-swap/}

step "Flutter build web (base-href=$BASE_HREF, 本地 canvaskit)"
# --no-web-resources-cdn: canvaskit.wasm 本地化 — Pages 上 gstatic 跨域虽然 CORS ok,
# 但本地化更稳, 离线也能跑
flutter build web --release --pwa-strategy=offline-first --base-href="$BASE_HREF" \
  --no-web-resources-cdn 2>&1 | tail -2

# 修 index.html 标题
sed -i '' \
  -e 's|<title>currency_exchange</title>|<title>Purr Swap · 换金所</title>|' \
  -e 's|content="currency_exchange"|content="Purr Swap · 换金所"|g' \
  -e 's|content="A new Flutter project."|content="USDT 多渠道比价 + 记账 + 风险提示"|' \
  build/web/index.html

# === Web 版自动更新 (Cache Busting) ===
# 让用户每次访问 https://kary2999.github.io/purr-swap/ 自动拿到最新版,
# 不必手动 Cmd+Shift+R。原理:
#   1) index.html 设 no-cache → 浏览器每次重新拉 index
#   2) 给 flutter_bootstrap.js 引用加 ?v=$VER → 版本变就拉新文件
#   3) flutter_bootstrap.js 内部加载 main.dart.js 也加 ?v=$VER → 同上
CUR_VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '\r')
step "Web 自更新: cache buster v=$CUR_VER"

# index.html: 注入 no-cache meta (放 charset 后,避免编码问题)
sed -i '' "/<meta charset/a\\
  <meta http-equiv=\"cache-control\" content=\"no-cache, no-store, must-revalidate\">\\
  <meta http-equiv=\"pragma\" content=\"no-cache\">\\
  <meta http-equiv=\"expires\" content=\"0\">
" build/web/index.html

# index.html: flutter_bootstrap.js?v=$VER
sed -i '' "s|flutter_bootstrap\\.js\"|flutter_bootstrap.js?v=$CUR_VER\"|g" \
  build/web/index.html

# flutter_bootstrap.js: 内部 "main.dart.js" 字面量加 ?v=$VER
# 关键: main.dart.js 默认无版本戳, GitHub Pages 给它 max-age=600 → 浏览器/SW 会缓存旧 bundle,
# 表现为 index 已是新版、但实际跑的代码还是旧的 ("看不到更新")。加 ?v= 让每版 URL 唯一,
# 彻底绕开浏览器 HTTP 缓存。(本项目用自定义 network-first SW, 无预缓存清单, ?v= 不冲突)
sed -i '' "s|\"main\\.dart\\.js\"|\"main.dart.js?v=$CUR_VER\"|g" \
  build/web/flutter_bootstrap.js

# === 自定义 Service Worker(恢复 PWA 可安装)===
# Flutter 3.41+ 内置 SW 已弃用为"自注销 stub"(无 fetch handler / 激活即 unregister),
# 导致 Chrome 不再判定为可安装 PWA。这里用自定义 SW 覆盖它:
#   · 带 fetch handler  → 满足 Chrome 可安装硬条件
#   · 网络优先          → 在线时始终拿最新版, 不会"看不到更新"
#   · 缓存兜底          → 离线时回退缓存, 仍可打开
# bootstrap 仍按 flutter_service_worker.js?v=<hash> 注册它, 浏览器按 query 取到此文件。
step "写入自定义 service worker (恢复 PWA 安装能力)"
cat > build/web/flutter_service_worker.js <<'SW_EOF'
'use strict';
// Purr Swap 自定义 SW — 网络优先 + 缓存兜底, 带 fetch handler 以满足 PWA 可安装条件。
const CACHE = 'purr-swap-runtime-v2';
self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', (event) => event.waitUntil((async () => {
  // 清掉旧版本缓存(含被缓存的旧 main.dart.js), 避免残留旧代码
  const keys = await caches.keys();
  await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
  await self.clients.claim();
})()));
self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  event.respondWith((async () => {
    try {
      const fresh = await fetch(req);
      if (fresh && fresh.status === 200 && req.url.startsWith(self.location.origin)) {
        const cache = await caches.open(CACHE);
        cache.put(req, fresh.clone());
      }
      return fresh;
    } catch (err) {
      const cached = await caches.match(req);
      if (cached) return cached;
      throw err;
    }
  })());
});
SW_EOF

# 给 build/web 加个 .nojekyll，让 GitHub Pages 不要 Jekyll 处理（保留 _flutter 等下划线开头目录）
touch build/web/.nojekyll

# 把 dist/version.json 复制过来 (app 自更新检测优先走 Pages 同源 fetch)
# 如果 release.sh 没跑过，dist/version.json 不存在 → 现场生成最简版
if [ -f dist/version.json ]; then
  cp dist/version.json build/web/version.json
else
  CUR_VER=$(grep '^version:' pubspec.yaml | awk '{print $2}' | tr -d '\r')
  cat > build/web/version.json <<JSON_EOF
{
  "latest": "${CUR_VER}",
  "android": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${CUR_VER}-Android.apk",
  "macos": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${CUR_VER}-macOS.dmg",
  "zip": "https://github.com/kary2999/purr-swap/raw/releases/PurrSwap-v${CUR_VER}-release.zip",
  "web": "https://kary2999.github.io/purr-swap/",
  "notes": "v${CUR_VER} (web build, $(date '+%Y-%m-%d'))"
}
JSON_EOF
fi

# README on the deployed branch (顺手)
cat > build/web/.deploy-info <<EOF
Purr Swap Web 部署
Built: $(date '+%Y-%m-%d %H:%M:%S %z')
Source commit: $(git rev-parse --short HEAD)
EOF

if [ "$MODE" != "deploy" ]; then
  step "build/web 已就绪 (未部署)"
  echo "  本地预览: cd build/web && python3 -m http.server 8000"
  echo "  部署到 gh-pages: ./scripts/release-web.sh deploy"
  exit 0
fi

step "部署到 gh-pages 分支"
TMP=$(mktemp -d -t purr-pages-XXXX)
cp -R build/web/. "$TMP/"
cd "$TMP"
git init -q -b gh-pages
git config user.name "kary2999"
git config user.email "kary2999@users.noreply.github.com"
git add .
git commit -q -m "deploy: gh-pages from $(date '+%Y-%m-%d %H:%M')"
git remote add origin git@github.com:kary2999/purr-swap.git
git push -f -u origin gh-pages 2>&1 | tail -5

step "✨ 部署完成"
echo "  访问: https://kary2999.github.io/purr-swap/"
echo "  ⚠️ 首次部署需在 https://github.com/kary2999/purr-swap/settings/pages"
echo "    Source 选 'Deploy from a branch' → Branch 选 'gh-pages' / 'root' → Save"
