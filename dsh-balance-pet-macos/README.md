# DSH 余额桌宠（macOS 原生版）

一个贴在桌面上的小挂件：角色举着一块平板，平板上实时显示 DeepSeek / DSH 余额。
余额每掉 **0.01 元**，角色就红闪 + 震动 + 播放打击音效，头顶飘出一个 `-0.01`。

原版（`VKmich16/V`）是 Windows PowerShell + WinForms 程序，在 macOS 上跑不了，
这个仓库是按同样的玩法用 **Swift + AppKit** 重写的原生实现：**零第三方依赖**、
约 1.4 MB 内存占用、不联网上传任何数据（只请求余额接口）。

![四种状态](docs/screenshots/01-connected.png)

---

## 快速开始

```bash
./build.sh                                   # 编译，无需网络
open "dist/DSH余额桌宠.app"                   # 启动
```

首次启动会出现在**主屏左下角**。之后会记住你拖到的位置。

> 需要 macOS 13+ 和 Xcode 命令行工具（`xcode-select --install`）。
> 已经编译好的 `dist/DSH余额桌宠.app` 可以直接双击运行。
> 没有 Dock 图标、没有菜单栏图标之外的存在感——退出请**右键宠物 → 退出**。

### 不看屏幕也能确认它在正常工作

```bash
"./dist/DSH余额桌宠.app/Contents/MacOS/DSHBalancePet" --windows
```

会打印余额、连接状态、凭证来源、窗口坐标 / 层级 / 是否可见。

---

## 操作

| 操作 | 效果 |
| --- | --- |
| 左键拖动 | 移动；松手后自动吸附回左下角（可在菜单里关掉） |
| 右键宠物 | 打开菜单（也可以在状态栏的 ¥ 图标上右键） |
| 透明区域 | 鼠标穿透，不挡你点别的窗口 |

右键菜单：

| 项目 | 说明 |
| --- | --- |
| 立即刷新余额 | 马上请求一次，平板直接跳到最新值，不补播动画 |
| 测试一次扣费 | 纯演示，播一次红闪 + 飘字 + 音效，不动真实余额 |
| 演示连续扣费 | `-0.05 / -0.1 / -0.2 / -0.5 / -1.0`，节奏和真实扣费完全一样，播完自动回到真实余额 |
| 尺寸 | 小 110 / 中 150 / 大 210 / 特大 280（pt） |
| 松手吸附左下角 | 开关 |
| 音效 | 开关 |
| 刷新间隔 | 10 秒 / 30 秒 / 1 分钟 / 5 分钟 |
| 设置 API Key… | 写入配置目录的 `apikey.txt`（权限 0600） |
| 重新读取凭证 | 改完凭证不用重启 |
| 打开日志 / 打开配置文件夹 | 排查问题用 |
| 退出 | 关闭 |

---

## 凭证是怎么拿到的

按顺序尝试，第一个成功的就用：

1. 环境变量 `DSHPET_KEY`
2. 应用目录下的 `apikey.txt`
3. 配置目录下的 `apikey.txt`（右键 → 设置 API Key 写的就是这个）
4. `~/.dsh/.credentials.yaml` 里的 `DEEPSEEK_API_KEY`
5. **`~/.dsh/.credentials.yaml` 里 DSH 自己的账号凭证**（`deepseek-account-platform/default`）

第 5 条是这台机器上实际生效的那条：DSH 是用**平台账号 token**登录的，
`~/.dsh/.credentials.yaml` 里根本没有 `DEEPSEEK_API_KEY`。所以本程序支持两种模式：

| 模式 | 端点 | 认证头 |
| --- | --- | --- |
| API Key（`sk-…`） | `https://api.deepseek.com/user/balance` | `Authorization: Bearer …` |
| DSH 账号凭证 | `<issuer>/api/v0/users/get_user_summary` | `x-dsh-auth-token: …` |

账号模式的响应是三层信封，余额在 `data.biz_data.normal_wallets`（外加 `bonus_wallets`），
平板显示的是两者 CNY 之和。这一点是从 DSH 自己的 `dsh-deepseek-account-platform`
插件里读出来的，不是猜的。

> **注意**：这条路径会读取你的 DSH 登录凭证，并且只把它发给凭证自身记录的
> `issuer`（即 `platform.deepseek.com`）。如果你不希望这样，把 `~/.dsh/.credentials.yaml`
> 里的账号记录删掉，改在第 1～3 条里放一个 `sk-` API Key 即可。

---

## 关于轮询频率（重要）

`platform.deepseek.com` 这个接口**有速率限制**：连续快速请求会返回 **429**。

所以默认轮询是 **30 秒**，而不是原版 Windows 版的 2 秒。命中 429 时会自动退避
（按 `Retry-After` 或翻倍，最多 5 分钟），并在日志里记一行。

余额下降时会**一分钱一分钱地扣**（每 0.2 秒一步，每步都有完整的动画 + 音效），
所以即使 30 秒才拉一次，看起来依然是连续掉钱。一次跳变超过 400 分（例如机器睡了
一整晚）会直接对齐，避免排队播几千次动画。

---

## 文件位置

| 路径 | 内容 |
| --- | --- |
| `~/Library/Application Support/DSHBalancePet/pet.log` | 每次请求的结果、启动信息 |
| `~/Library/Application Support/DSHBalancePet/state.json` | 尺寸、开关、窗口位置 |
| `~/Library/Application Support/DSHBalancePet/status.json` | 运行时状态（约每秒刷新） |
| `~/Library/Application Support/DSHBalancePet/apikey.txt` | 只有你手动设置过才存在 |

设 `DSHPET_HOME=/some/dir` 可以把上面这些全部改到指定目录（便携模式）。
卸载 = 删掉 `.app` + 上面这个目录。

---

## 诊断与自测

```bash
BIN="./dist/DSH余额桌宠.app/Contents/MacOS/DSHBalancePet"

"$BIN" --selftest     # 14 项断言：记账不漂移、到账、四舍五入、点击穿透区域
"$BIN" --check        # 打印凭证来源，真实请求一次并显示余额
"$BIN" --screens      # 打印 NSScreen 布局（多显示器排查）
"$BIN" --snapshot DIR # 离屏渲染 4 张 PNG，不需要录屏权限
"$BIN" --windows      # 读取运行中实例的状态文件
"$BIN" --reset        # 清除保存的窗口位置
```

`--snapshot` 会渲染 4 种状态：已连接、扣费中、到账、未配置凭证。

## 源码结构

```
Sources/
├── AppConfig.swift      路径、日志、凭证解析（含 YAML 账号记录解析）、状态持久化
├── BalanceClient.swift  两种模式的 HTTP + 响应解析、429 处理
├── PetModel.swift       以「分」为单位的记账 + 动画状态机
├── PetView.swift        角色/平板/飘字绘制、拖动、右键、点击穿透
├── PetController.swift  窗口、菜单、状态栏、轮询、音效
├── Diagnostics.swift    自测 / 真实请求 / 离屏渲染 / 屏幕诊断
└── main.swift           入口
tools/make_hit_sound.py  纯标准库生成打击音效（不含任何第三方素材）
```

角色、平板、飘字全部是用 Core Graphics 画出来的，音效是脚本合成的，
所以这个仓库**不包含任何第三方美术或音频素材**。

---

## 已知边界

- 只在 Apple Silicon 上验证过（`arm64-apple-macos13.0`）。Intel 也可以编译，
  把 `build.sh` 里的 `-target` 换成 `x86_64-apple-macos13.0` 即可。
- 右键菜单需要 AppKit 把应用激活才弹得出来，所以右键的瞬间 DSH 余额桌宠会成为
  前台应用（`.accessory` 模式，不会出现 Dock 图标）。
- 余额接口返回的是字符串精度（`"38.6177023600000000"`），显示按四舍五入到分。
