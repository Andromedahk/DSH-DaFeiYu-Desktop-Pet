# DSH大肥鱼桌宠

一个用于 **DeepSeek Harness** 的 macOS 原生余额桌宠。角色手持平板显示余额，扣费时播放受击动画与原版音效，充值时显示提示。使用 Swift + AppKit 开发，无第三方运行时依赖。

**当前版本 v1.5.0**：支持蓝色大肥鱼、GPT龙娘、大小姐Claude、北美猫娘Gemini四个角色；蓝色大肥鱼换成表情立绘，平时开心、失去焦点生气、扣费时紧张；未连接时显示抱盆图；拖动松手吸附左下角；桌宠与 DeepSeek Harness 窗口绑定，DSH 窗口最小化或关闭时自动隐藏。

## 四个角色

以下为应用实际渲染的四角色拼图，使用统一示例余额，不包含真实账号信息。

[![四个角色使用预览](dsh-balance-pet-macos/docs/previews/four-characters-usage.webp)](dsh-balance-pet-macos/docs/screenshots/four-characters-usage.png)

<table>
  <tr><th width="50%">蓝色大肥鱼</th><th width="50%">GPT龙娘</th></tr>
  <tr>
    <td align="center" width="50%"><a href="dsh-balance-pet-macos/Resources/expression_happy.png"><img src="dsh-balance-pet-macos/docs/previews/sprite.webp" alt="蓝色大肥鱼（平时）" width="360" height="270"></a></td>
    <td align="center" width="50%"><a href="dsh-balance-pet-macos/Resources/sprite-gpt.png"><img src="dsh-balance-pet-macos/docs/previews/sprite-gpt.webp" alt="GPT龙娘" width="360" height="270"></a></td>
  </tr>
  <tr><th width="50%">大小姐Claude</th><th width="50%">北美猫娘Gemini</th></tr>
  <tr>
    <td align="center" width="50%"><a href="dsh-balance-pet-macos/Resources/sprite-claude.png"><img src="dsh-balance-pet-macos/docs/previews/sprite-claude.webp" alt="大小姐Claude" width="360" height="270"></a></td>
    <td align="center" width="50%"><a href="dsh-balance-pet-macos/Resources/sprite-gemini.png"><img src="dsh-balance-pet-macos/docs/previews/sprite-gemini.webp" alt="北美猫娘Gemini" width="360" height="270"></a></td>
  </tr>
</table>

原始透明 PNG 均包含在 [`Resources`](dsh-balance-pet-macos/Resources) 文件夹中；上表图片可点击查看原图。蓝色大肥鱼的旧版单张立绘 `sprite.png` 仍保留在 `Resources` 里，仅作历史素材，应用已改用表情立绘。

**切换方法：** 右键桌宠，或点击菜单栏 **¥ → 切换角色**。选择立即生效，重启后自动恢复；切换保留余额、动画、窗口位置和尺寸。

蓝色大肥鱼在未配置 API Key / 账号凭证、连接中或连接失败时，改为显示抱盆图，不显示余额标题、金额、状态点或金额飘字；连接成功后自动恢复手持平板和余额显示。其他三个角色保持原有显示方式。

[![大肥鱼未连接状态](dsh-balance-pet-macos/docs/previews/deepseek-offline.webp)](dsh-balance-pet-macos/docs/screenshots/deepseek-offline.png)

## 蓝色大肥鱼的三种表情

[![三种表情](dsh-balance-pet-macos/docs/previews/expressions.webp)](dsh-balance-pet-macos/Resources/expression_happy.png)

| 表情 | 触发条件 |
| --- | --- |
| 平时（`expression_happy.png`） | 默认状态 |
| 紧张（`expression_nervous.png`） | 发生扣费时，动画期间并额外保持 1 秒 |
| 生气（`expression_angry.png`） | DSH 窗口仍然可见、但当前前台不是 DSH 时；DSH 最小化或关闭时桌宠直接隐藏，不会显示生气 |

表情切换只换立绘，平板上的余额、飘字、受击抖动照常。表情立绘为 1024 × 1024，窗口宽度按立绘比例自动调整；其他三个角色仍是单张 1536 × 1024 立绘，不受影响。

## 更新记录

### v1.5.0 · 蓝色大肥鱼表情立绘

- 蓝色大肥鱼换成三张表情立绘：平时开心、失去焦点生气、扣费时紧张；扣费动画结束后紧张表情再保持 1 秒。
- 表情由 DSH 窗口焦点与扣费状态自动切换，平板余额、状态点、飘字和受击抖动都保留，文字坐标按新立绘重新测量。
- 1024 × 1024 的方形立绘让窗口宽度随角色比例变化；切换到其他三个 1536 × 1024 角色时窗口自动恢复，高度和左下角锚点不变。
- 未连接时的抱盆图保持不变，按比例居中显示在方形窗口内。
- 吸附改为底部贴紧屏幕边缘，左侧仍留 14 pt 间距：窗口为了浮字在立绘下方留了 3% 的空白，吸附时把这部分补掉，贴角时脚下不再悬空。
- 自检新增表情渲染差异、表情切换规则与「扣费后多保持一秒」的回归项；`verify.sh` 增加三张表情图的 SHA-256 校验。

### v1.4.0 · 跟随 DSH 窗口显示

- 新增「跟随 DSH 窗口显示」，默认开启：只有 DeepSeek Harness（`com.deepseek.dsh`）有窗口显示在屏幕上时才显示桌宠。
- DSH 窗口最小化、关闭、退出或切到其他桌面空间时自动隐藏桌宠；DSH 窗口重新出现时自动恢复，不需要重启应用。
- DSH 失去焦点（切到浏览器、终端等其他 App）时桌宠保持原位，不隐藏也不移动；该联动只管显示与隐藏，不跟随窗口位置。
- 检测使用窗口服务器的在屏窗口列表，**不需要辅助功能或屏幕录制权限**；读取不到窗口列表时按「可见」处理，不会误隐藏。
- 桌宠隐藏期间不播放受击音效；右键菜单新增开关，关闭后桌宠常驻。

### v1.3.2 · 吸附左下角修复

- 修复拖动松手后不会吸附回左下角的问题；右键菜单里的「吸附回左下角」同样受影响，现已一并恢复。
- 原因：窗口动画用 `NSWindow` 的 animator 代理设置 `frameOrigin`，而这个属性不可动画，调用被静默忽略，窗口原地不动。改为动画整个 frame，并在动画结束时兜底对齐最终位置。
- 多显示器行为不变：吸附目标仍是桌宠当前所在屏幕的左下角。

### v1.3.1 · 离线抱盆状态

- 蓝色大肥鱼在未配置 API Key / 账号凭证、连接中或连接失败时，使用上方抱盆图。
- 隐藏余额标题、金额、状态点及金额飘字；连接成功后自动恢复平板图和余额。
- 透明点击区域随图片切换，其他三个角色不变。
- README 使用轻量预览图与固定尺寸的双列表格，点击图片仍可查看完整 PNG。

### v1.3.0 · 四角色切换

- 新增 GPT龙娘、大小姐Claude、北美猫娘Gemini，与蓝色大肥鱼共四个角色。
- 通过桌宠右键菜单或菜单栏即时切换，重启后保留选择。
- 切换保留余额、动画、位置及尺寸；加入四角色使用截图和透明原图展示。

## 下载与运行

前往 [最新 Release](https://github.com/Andromedahk/DSH-DaFeiYu-Desktop-Pet/releases/latest)，下载 `DSH-DaFeiYu-macOS.zip`，解压后将 **DSH大肥鱼桌宠.app** 放入“应用程序”并打开。

- 支持 **macOS 13 及以上**；发布包同时包含 Apple Silicon 与 Intel 架构。
- 应用可读取本机 DeepSeek Harness 凭证，独立运行；默认跟随 DSH 窗口显示，可在菜单里关闭该联动后单独使用。具体配置见 [macOS 使用说明](dsh-balance-pet-macos/README.md#凭证与余额)。
- 应用使用本地临时签名，尚未经过 Apple 开发者签名和公证。首次打开可能被系统拦截；确认下载来源后，可在“系统设置 → 隐私与安全性”中允许打开。

## 日常操作

| 操作 | 功能 |
| --- | --- |
| 左键拖动 | 移动桌宠；默认松手吸附当前屏幕左下角，可在菜单关闭 |
| 右键 / Control + 单击 | 打开菜单，切换角色、尺寸及音效等 |
| 菜单栏 ¥ | 查看余额状态、刷新余额或打开操作菜单 |
| 测试一次扣费 / 演示连续扣费 | 本地演示动画，不发起真实扣费 |

角色透明区域支持鼠标穿透，余额文字随手持平板倾斜和震动，长金额自动缩小显示。

桌宠默认与 **DeepSeek Harness 窗口**绑定：只有当 DSH 有窗口显示在屏幕上时才出现；DSH 窗口最小化、关闭、退出或切到其他桌面空间时自动隐藏，窗口回来时自动恢复。**切到别的 App 但 DSH 窗口仍然可见时，桌宠保持原位不动**，不会隐藏也不会跳动。该联动只控制显示与隐藏，不跟随窗口移动；可在右键菜单里关闭「跟随 DSH 窗口显示」。

## 从源码构建

安装 Xcode Command Line Tools 后运行：

```sh
cd dsh-balance-pet-macos
ARCH=universal ./build.sh
./verify.sh
open "dist/DSH大肥鱼桌宠.app"
```

省略 `ARCH=universal` 时只构建当前机器架构。离线验证使用独立临时配置，检查四角色资源、切换绘制、配置恢复、余额逻辑、签名和启动行为。

## 文档与来源

- [macOS 版源码与完整使用说明](dsh-balance-pet-macos/README.md)
- [代码审查与验证记录](dsh-balance-pet-macos/docs/REVIEW.md)
- [角色素材来源与文件哈希](dsh-balance-pet-macos/Resources/README.md)
- [Windows 原版存档](原版（Windows版）/DSH余额桌宠/先看这里（快速开始）.md)

本项目基于 [VKmich16/V](https://github.com/VKmich16/V) 的 Windows 原版移植，感谢原作者。原版代码和素材完整保留在 `原版（Windows版）` 目录；缓存、编译产物及个人凭证不纳入版本控制。

上游暂未附带许可证；本仓库保留来源说明，不对上游代码和素材另行授予许可。
