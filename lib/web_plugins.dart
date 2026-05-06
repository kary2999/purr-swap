// Web 插件手动注册 — 绕过 Flutter 3.41 web build 的 auto-register bug
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:shared_preferences_web/shared_preferences_web.dart';
import 'package:url_launcher_web/url_launcher_web.dart';

void registerWebPlugins() {
  // ZZZ_WEB_PLUGINS_REGISTERED_MARKER_0421
  SharedPreferencesPlugin.registerWith(webPluginRegistrar);
  UrlLauncherPlugin.registerWith(webPluginRegistrar);
}
