# 触控板助手 / PadKit

一个开源、轻量的 macOS 菜单栏工具(Apple Silicon,macOS 13+),用多指触控板手势触发自定义动作,思路类似 BetterTouchTool 的触控板手势。**完全独立实现**,不含任何 BTT 代码或资源。

## 支持的手势

| 手势 | 配置键 | 默认动作 |
|---|---|---|
| 三指轻点 | `tap3` | 鼠标中键 |
| 四指轻点 | `tap4` | 快捷键 `ctrl+up`(调度中心) |
| 五指轻点 | `tap5` | Shell:`open ~/Downloads` |
| 三指按下 / 四指按下(物理点击) | `click3` / `click4` | 无 |
| 三指上/下/左/右滑 | `swipe3Up/Down/Left/Right` | 最大化 / 无 / 窗口左半屏 / 窗口右半屏 |
| 四指上/下/左/右滑 | `swipe4Up/Down/Left/Right` | 无 |
| TipTap 左/右(一指按住,另一指在其左/右侧轻点) | `tipTapLeft` / `tipTapRight` | `cmd+shift+[` / `cmd+shift+]`(切换标签页) |

## 支持的动作

`none`(无)、`shortcut`(键盘快捷键,如 `cmd+shift+t`、`ctrl+left`、`f11`)、`middleClick`(鼠标中键)、`launchApp`(应用名 / bundle id / 路径)、`shell`(用 `zsh -lc` 执行)、`snapLeft` / `snapRight` / `maximize`(通过辅助功能 API 移动前台窗口)。

快捷键修饰键:`cmd` `shift` `ctrl` `opt`/`alt` `fn`;按键:字母、数字、标点、`left/right/up/down`、`space`、`tab`、`return`、`esc`、`delete`、`f1`–`f12`、`home/end/pageup/pagedown`。

## 编译(只需 Xcode Command Line Tools)

```bash
xcode-select --install   # 如未安装
git clone https://github.com/zilonghe/padkit.git
cd padkit
./build.sh
```

产物:`build/PadKit.app` 和 `PadKit.zip`。

## 安装

1. 把 `build/PadKit.app` 拖到 `/应用程序`(登录时启动功能要求 App 位于固定位置,推荐 /Applications)。
2. 首次打开:应用是 ad-hoc 签名、未经公证,双击可能提示“无法验证开发者”。请在 Finder 中 **右键(或 Control+点按)PadKit.app → 打开 → 打开**。如仍被拦截,到 系统设置 › 隐私与安全性 底部点“仍要打开”,或执行 `xattr -dr com.apple.quarantine /Applications/PadKit.app`。
3. 菜单栏会出现一个“手指点按”图标。

## 权限

PadKit 需要 **辅助功能** 权限(发送快捷键、模拟中键、拦截多指点击、移动窗口):

**系统设置 › 隐私与安全性 › 辅助功能** → 打开 PadKit 的开关(没有就点 “+” 添加 /Applications/PadKit.app)。

首次启动会弹出说明并跳转。授权后无需重启。

> 注意:每次重新编译/重新签名后 ad-hoc 签名会改变,macOS 可能认为是新应用,需要在辅助功能列表里**先删除旧的 PadKit 再重新添加**。

## 配置

配置文件:`~/Library/Application Support/PadKit/config.json`(首次运行自动生成默认配置)。可在菜单栏 › 设置… 中图形化编辑并“保存”,也可直接编辑 JSON 后在设置里点“重新载入”。

```json
{
  "enabled" : true,
  "swipeThreshold" : 0.12,
  "tapMaxDuration" : 0.3,
  "mappings" : {
    "tap3" : { "type" : "middleClick", "value" : "" },
    "swipe3Left" : { "type" : "snapLeft", "value" : "" },
    "tipTapRight" : { "type" : "shortcut", "value" : "cmd+shift+]" }
  }
}
```

## 与系统手势冲突

macOS 自带三/四指手势(调度中心、切换桌面、三指拖移、查询)。PadKit **不会屏蔽**系统手势(私有触控 API 只能读取),建议到 系统设置 › 触控板 › 更多手势 中关闭与你映射冲突的系统手势,或者改用四指 / TipTap。

## 菜单栏

启用手势 · 登录时启动(SMAppService)· 设置… · 重新连接触控板 · 检查辅助功能权限 · 退出

## 实现说明

- 通过 `dlopen` 加载私有框架 `MultitouchSupport.framework`,使用 `MTDeviceCreateList` / `MTRegisterContactFrameCallback` / `MTDeviceStart` 获取原始触点(数据结构参照 MiddleClick 等开源项目的公开描述)。
- 多指点击通过 `CGEventTap` 在左键按下时查询当前手指数并(若已映射)吞掉原点击。
- 私有 API 可能在未来 macOS 版本中变化。

## License

MIT
