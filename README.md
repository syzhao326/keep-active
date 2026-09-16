# keepactive

一个装在 Mac 上的小工具：在**没人操作电脑**的时候，自动小幅移动鼠标，并（可选）把飞书切到前台、在文档里打一段固定的话再自动删掉，让电脑后台看起来一直有人在用。**真人一碰鼠标键盘，程序立刻让位**，不会跟你抢。

- 🍎 原生 macOS 程序，**不依赖 Python 等任何环境**
- 💻 通用二进制，Intel 和 Apple Silicon 的 Mac 都能跑
- 🧠 只在电脑空闲时才动手；间隔和节奏都随机化，不像机器那样死板
- 🔒 只在本机模拟你自己的鼠标键盘，**不联网、不上传任何数据、不改系统设置**

## 有两个版本，怎么选？

| 版本 | 适合谁 | 怎么用 |
|---|---|---|
| **① 菜单栏 App（推荐）** | **打不开「终端」、或打开终端要审批的电脑** | 下载、双击运行，点菜单栏图标开始/停止 |
| ② 命令行版 | 会用终端的人 | 终端里一行命令启动/停止 |

---

# ① 菜单栏 App（无需终端）

双击运行，程序常驻屏幕顶部菜单栏；点一下图标就能「开始 / 暂停」，全程不用打开终端。

## 下载

**下载地址（点开后会自动下载一个压缩包）：**

👉 https://github.com/syzhao326/keep-active/releases/latest/download/MeetingNotes.app.zip

下载后在「访达」里**双击这个压缩包**解压，得到 **MeetingNotes.app**。建议把它拖到「应用程序」文件夹里。

## 第一次打开（重要）

因为这是个人自制小程序、没有花钱做苹果认证，第一次打开需要手动允许一下：

1. **双击 MeetingNotes**。如果弹出 “Apple 无法验证……是否包含恶意软件”，点 **“完成”**（先别点“移到废纸篓”）。
2. 打开 **系统设置 → 隐私与安全性**，向下滚动到「安全性」区域，会看到一行 “已阻止使用 MeetingNotes……”，点右边的 **“仍要打开”**，按提示用指纹或密码确认。
3. 这时 MeetingNotes 就会启动，屏幕**右上角菜单栏**会出现一个小文稿图标 📝。

> 💡 想省掉上面这几步？如果家里人能帮忙，把 **MeetingNotes.app 用 U 盘**拷到她电脑的「应用程序」里（用 U 盘拷贝不会被系统标记为“从网上下载”），就能直接双击打开，跳过“仍要打开”。

## 授予「辅助功能」权限（必须做一次）

macOS 规定：模拟鼠标键盘必须先授权，否则程序开着也没效果。

1. 第一次启动时，程序会自动弹窗提示，并帮你打开 **系统设置 → 隐私与安全性 → 辅助功能**。
2. 在列表里找到 **MeetingNotes**，把右边的**开关打开**。
   - 如果列表里没有它：点列表下方的「**＋**」，在「应用程序」里选中 MeetingNotes 再打开开关。
3. 打开开关后，程序会**自动开始工作**（无需重启）。菜单栏图标变成实心 📝 就表示正在运行。

## 平时怎么用

点菜单栏那个小文稿图标，会看到菜单：

- **开始 / 暂停** — 随时手动开关
- **试打飞书一次** — 先打开飞书文档、光标点进正文，再点这个，会当面打一段字再自动删掉，用来验证
- **打开配置文件…** — 修改要自动输入的那段话等设置
- **开机时自动运行** — 打上勾，以后开机自动启动，再也不用管
- **退出** — 完全退出程序

> 需要临时停用（比如同事路过、或正在真人打字），点一下「暂停」即可；真人操作时程序本来也会自动让位。

---

# ② 命令行版（会用终端的人）

打开「终端」，粘贴这一行回车安装：

```bash
curl -fsSL https://raw.githubusercontent.com/syzhao326/keep-active/main/install.sh | bash
```

装完按提示先授权、再启动。常用命令：

```bash
keepactive start
```

```bash
keepactive stop
```

```bash
keepactive status
```

| 命令 | 作用 |
|---|---|
| `keepactive start` | 后台启动（之后可关掉终端窗口） |
| `keepactive stop` | 停止 |
| `keepactive status` | 查看状态 + 最近日志 |
| `keepactive test-feishu` | 立刻试打一次飞书 |
| `keepactive selftest` | 自检，不模拟任何操作 |
| `keepactive config` | 查看配置文件 |

---

# ⚙️ 配置

两个版本各自独立、格式相同：

- **菜单栏版**：`~/Library/Application Support/MeetingNotes/config.json`（点菜单「打开配置文件…」也能直接打开它）。改完点「暂停」再「开始」生效。
- **命令行版**：`~/Library/Application Support/KeepActive/config.json`。改完 `keepactive stop` 再 `keepactive start` 生效。

| 字段 | 含义 | 默认 |
|---|---|---|
| `jiggleIdleMin` / `jiggleIdleMax` | 空闲多少秒后开始动鼠标（区间内随机） | 35 / 65 |
| `feishuEnabled` | 是否开启飞书打字（设为 `false` 就**只动鼠标，最省心**） | `true` |
| `feishuText` | 固定输入的那段话（建议纯中文、不含换行和括号引号） | 一段工作汇报 |
| `feishuDocURL` | 可选：打字前先打开的文档链接。留空则只切到飞书、打进当前光标处（**推荐留空**） | 空 |
| `typeIntervalMin` / `typeIntervalMax` | 两次打字间隔（秒） | 240 / 600 |
| `autoUndo` | 打完是否自动删除 | `true` |
| `charDelayMin` / `charDelayMax` | 每个字之间的间隔（秒），越大打得越慢越像人 | 0.06 / 0.18 |

**只想要动鼠标、完全不碰飞书**：把 `feishuEnabled` 改成 `false`，最简单也最不容易出问题。

---

# 🧠 工作原理

- **动鼠标**：定时检查「距上次鼠标键盘操作过了多久」。只要有人在用，这个计时一直被清零，程序就不动手；等真的没人碰、空闲超过阈值（默认 35~65 秒随机），才小幅移动一下鼠标（带随机曲线和抖动，用完归位）。
- **打字**：默认每 4~10 分钟一次，但**动手前会先静默观察 3 秒**确认没人在用，才把飞书切到前台打字，打完按设置自动删除。那一刻有人在用就自动跳过。
- **安全护栏**：打字前会确认飞书确实在最前面，否则**绝不打字**，避免误打进别的软件。
- 关机 / 重启后不会自动运行（除非勾了「开机时自动运行」）。

---

# ⚠️ 注意事项

- 这类「防挂机」工具（俗称 mouse jiggler）网上和 App Store 有很多现成的，原理一致，本项目是按需求定制、供个人在自己电脑上使用。
- 如果监控不只看鼠标空闲，还会**截屏**或看飞书文档的**编辑记录**，那么每隔几分钟一次内容相同的编辑，规律性反而明显。担心的话：把 `feishuEnabled` 设为 `false` 只靠鼠标微动保持在线，或把 `feishuDocURL` 指向一个只有本人能看到的私人文档。
- 如果是公司统一管理（MDM）的电脑，可能连「辅助功能」授权或打开未知来源 App 都被限制，那样任何同类工具都无法运行，这与本工具无关。

---

# 🛠️ 从源码编译（可选）

需要 Xcode 命令行工具（`xcode-select --install`）。

命令行版：

```bash
swiftc -O main.swift -o keepactive
codesign --force --sign - --identifier com.keepactive.cli keepactive
```

菜单栏 App：

```bash
bash build-app.sh
```

---

# 🧹 卸载

- 菜单栏版：点图标 →「退出」；把 MeetingNotes.app 拖进废纸篓；到「系统设置 → 隐私与安全性 → 辅助功能」移除它的条目；如需彻底清理，删除 `~/Library/Application Support/MeetingNotes` 文件夹。
- 命令行版：`keepactive stop`，再 `rm -rf "$HOME/Library/Application Support/KeepActive"`，并从 `~/.zshrc` 删掉 `alias keepactive=...` 那行。

---

## 📄 License

[MIT](LICENSE)
