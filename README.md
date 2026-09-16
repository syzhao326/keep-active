# keepactive

一个装在 Mac 上的小工具：在**没人操作电脑**的时候，自动小幅移动鼠标，并（可选）把飞书切到前台、在文档里打一段固定的话再自动删掉，让电脑后台看起来一直有人在用。**真人一碰鼠标键盘，程序立刻让位**，不会跟你抢。

- 🍎 原生 macOS 程序，**不依赖 Python 等任何环境**
- 💻 通用二进制，Intel 和 Apple Silicon 的 Mac 都能跑
- 🧠 只在电脑空闲时才动手；间隔和节奏都随机化，不像机器那样死板
- ⌨️ 命令行一行启动、一行停止；运行期间随时可以自己接管电脑
- 🔒 只在本机模拟你自己的鼠标键盘，**不联网、不上传任何数据、不改系统设置**

---

## 🚀 最快的安装方式（推荐给非技术用户）

打开系统自带的「**终端**」App（在「启动台」搜索「终端」，或在「应用程序 → 实用工具」里），把下面这一行粘贴进去、回车：

```bash
curl -fsSL https://raw.githubusercontent.com/syzhao326/keep-active/main/install.sh | bash
```

装完后，终端会打印出**接下来的两步**，照着做即可（见下方「授予权限」一节）。

> 也可以把 [给AI的安装提示词.md](给AI的安装提示词.md) 里的提示词复制给你电脑上的 AI（ChatGPT / Codex 等），让它一步步帮你装好。

---

## 🔑 授予「辅助功能」权限（必须做一次）

macOS 规定：**模拟鼠标键盘必须有「辅助功能」权限**，否则程序跑了也不生效。

1. 运行一次启动命令，它会**自动弹出系统设置**并给出提示：

   ```bash
   "$HOME/Library/Application Support/KeepActive/keepactive" start
   ```

2. 在弹出的「**系统设置 → 隐私与安全性 → 辅助功能**」里：
   - 找到 **keepactive**，把它右边的开关**打开**；
   - 如果列表里没有它：点列表下方的「**＋**」，定位到终端里打印出来的那个文件（`.../KeepActive/keepactive`），选中并打开开关。

3. 打开开关后，**再运行一次** `start` 命令，就真正在后台启动了。之后可以关掉终端窗口。

---

## 🕹️ 日常使用

如果你用了安装脚本，它已经帮你设好别名，新开终端窗口后可直接：

```bash
keepactive start
```

```bash
keepactive stop
```

```bash
keepactive status
```

> 没设别名时，把 `keepactive` 换成完整路径 `"$HOME/Library/Application Support/KeepActive/keepactive"`。

| 命令 | 作用 |
|---|---|
| `keepactive start` | 后台启动（之后可关掉终端窗口） |
| `keepactive stop` | 停止 |
| `keepactive status` | 查看是否在运行 + 最近日志 |
| `keepactive run` | 在前台运行，方便观察（Ctrl+C 停止） |
| `keepactive test-feishu` | 立刻试打一次飞书（第一次用来验证） |
| `keepactive selftest` | 自检，不会模拟任何操作 |
| `keepactive config` | 查看配置文件路径与内容 |

---

## ✍️ 第一次先试打一次飞书

1. 打开你要写入的那个飞书文档，**把光标点进正文里**；
2. 运行：

   ```bash
   keepactive test-feishu
   ```

它会在 3 秒后把飞书切到前台，打出那段话、停顿一下，再一个字一个字自动删掉。亲眼确认「文字打对了、也删干净了」，就说明一切正常。

---

## ⚙️ 配置

配置文件在：`~/Library/Application Support/KeepActive/config.json`。用「文本编辑」打开修改，改完执行 `keepactive stop` 再 `keepactive start` 生效。

| 字段 | 含义 | 默认 |
|---|---|---|
| `jiggleIdleMin` / `jiggleIdleMax` | 空闲多少秒后开始动鼠标（区间内随机） | 35 / 65 |
| `feishuEnabled` | 是否开启飞书打字（设为 `false` 就**只动鼠标，最省心**） | `true` |
| `feishuText` | 固定输入的那段话（建议纯中文、不含换行和括号引号） | 一段工作汇报 |
| `feishuDocURL` | 可选：打字前先打开的文档链接。留空则只切到飞书、打进当前光标处（**推荐留空**，让文档保持打开更可靠） | 空 |
| `typeIntervalMin` / `typeIntervalMax` | 两次打字间隔（秒） | 240 / 600 |
| `autoUndo` | 打完是否自动删除 | `true` |
| `charDelayMin` / `charDelayMax` | 每个字之间的间隔（秒），越大打得越慢越像人 | 0.06 / 0.18 |

**只想要动鼠标、完全不碰飞书**：把 `feishuEnabled` 改成 `false`。这样最简单，也最不容易出问题。

---

## 🧠 工作原理

- **动鼠标**：定时检查「距上次鼠标键盘操作过了多久」。只要有人在用，这个计时一直被清零，程序就一直不动手；等到真的没人碰、空闲超过阈值（默认 35~65 秒随机），才小幅移动一下鼠标（带一点随机曲线和抖动，用完归位）。
- **打字**：默认每 4~10 分钟一次，但**动手前会先静默观察 3 秒**，确认确实没人在用，才把飞书切到前台打字，打完按设置自动删除。那一刻如果有人在用，就自动跳过、稍后再看。
- **安全护栏**：打字前会确认飞书确实在最前面，否则**绝不打字**，避免把文字误打进别的软件。
- 关机 / 重启后**不会**自动运行，需要重新 `start`（有意为之，避免你忘了它一直在跑）。

---

## ⚠️ 注意事项

- 这类「防挂机」工具（俗称 mouse jiggler）网上和 App Store 有很多现成的，原理一致，本项目是按需求定制的版本，供个人在自己的电脑上使用。
- 如果监控不只看鼠标空闲，还会**截屏**或查看飞书文档的**编辑记录**，那么每隔几分钟一次内容相同的编辑，规律性反而明显。担心的话建议：把 `feishuEnabled` 设为 `false` 只靠鼠标微动保持「在线」，或把 `feishuDocURL` 指向一个只有本人能看到的私人文档。
- 首次从别处拷贝二进制到新机器，若提示「无法打开、开发者无法验证」，先执行：`xattr -dr com.apple.quarantine "$HOME/Library/Application Support/KeepActive/keepactive"`。

---

## 🛠️ 从源码编译（可选）

需要 Xcode 命令行工具（`xcode-select --install`）：

```bash
swiftc -O main.swift -o keepactive
codesign --force --sign - --identifier com.keepactive.cli keepactive
```

编译通用二进制（Intel + Apple Silicon）：

```bash
swiftc -O -target arm64-apple-macos12 main.swift -o ka-arm64
swiftc -O -target x86_64-apple-macos12 main.swift -o ka-x86_64
lipo -create ka-arm64 ka-x86_64 -output keepactive && rm ka-arm64 ka-x86_64
codesign --force --sign - --identifier com.keepactive.cli keepactive
```

---

## 🧹 卸载

```bash
keepactive stop
rm -rf "$HOME/Library/Application Support/KeepActive"
```

再到「系统设置 → 隐私与安全性 → 辅助功能」把 keepactive 的条目移除（选中后点「－」）。如果之前加过 zsh 别名，再从 `~/.zshrc` 里删掉那行 `alias keepactive=...` 即可。

---

## 📄 License

[MIT](LICENSE)
