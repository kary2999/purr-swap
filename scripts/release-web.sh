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
flutter build web --release --pwa-strategy=none --base-href="$BASE_HREF" \
  --no-web-resources-cdn 2>&1 | tail -2

# 修 index.html 标题
sed -i '' \
  -e 's|<title>currency_exchange</title>|<title>Purr Swap · 换金所</title>|' \
  -e 's|content="currency_exchange"|content="Purr Swap · 换金所"|g' \
  -e 's|content="A new Flutter project."|content="USDT 多渠道比价 + 记账 + 风险提示"|' \
  build/web/index.html

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
