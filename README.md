# Purr Swap · 换金所

> USDT 多渠道比价 + 记账 + 风险提示。让换汇从「凭感觉」变成「看数据」。

基于 **Flutter 3.19+** 跨平台构建，已发布 Android / macOS / Web 三端。当前版本 **v0.2.9**。

---

## 下载

去 [Releases](../../releases/latest) 直接下载对应平台产物：

| 平台 | 文件 | 要求 |
|---|---|---|
| 📱 Android | `PurrSwap-v0.2.9-Android.apk` | Android 7.0+ |
| 🖥 macOS | `PurrSwap-v0.2.9-macOS.dmg` | macOS 10.14+（M1–M4 / Intel 通用） |
| 🌐 Web/源码 | `PurrSwap-v0.2.9-release.zip` | 任意浏览器，解压后启 web server |

每个产物配 `.sha256` 校验文件，介意完整性可用 `shasum -a 256 -c <file>.sha256` 比对。

### macOS 首次打开提示「无法验证开发者」

```bash
# 右键 App → 打开 → 打开（一次后系统记住），或
sudo xattr -rd com.apple.quarantine "/Applications/Purr Swap.app"
```

---

## 核心功能

| Tab | 作用 |
|---|---|
| ⭐ 预测 | 基于历史汇率生成短期走势预判，辅助择时 |
| 📝 记一笔 | 一键归档每笔换汇的金额、渠道、汇率、手续费 |
| 📊 历史 | 可检索的全量流水，支持按渠道 / 时间筛选 |
| 📈 统计 | 累计成本、平均汇率、渠道分布曲线 |
| 📖 指南 | 各渠道操作步骤 + 已知风险点 |
| ⚙️ 设置 | 数据导入 / 导出 / 清空 |

数据来源：**Binance C2C / OKX C2C / Panda Remit / Visa FX / Wise** 五条公开行情。

---

## 隐私

所有数据**仅本地存储**（`shared_preferences` + 设备文件系统），不上传任何后端。卸载即清空 —— 重要数据请定期 **设置 → 导出备份**。

---

## 自己跑起来

```bash
flutter pub get
flutter run               # 当前平台
flutter run -d chrome     # web
flutter build apk         # Android release
flutter build macos       # macOS release
```

需要 Flutter SDK ≥ 3.19，Dart ≥ 3.3。

---

## License

[MIT](LICENSE)
