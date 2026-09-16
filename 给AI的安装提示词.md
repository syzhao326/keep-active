# 给「她电脑上的 AI」的安装提示词

把下面**方框里的全部内容**复制，粘贴到你电脑上的 AI 助手里（Codex、ChatGPT、Claude 等都行），发送给它，它会一步步帮你装好。

> 如果你用的是能直接操作终端的 AI（例如 Codex CLI），它会帮你执行命令；
> 如果你用的是普通网页版 ChatGPT（不能操作你的电脑），它会把每一步要在「终端」App 里运行的命令告诉你，你照着复制粘贴到终端里回车即可。

---

```
你好，我想在这台 Mac 上安装一个我先生帮我做的小工具，叫 keepactive。

它的作用：当我一段时间没碰电脑时，自动小幅移动一下鼠标（还可以在飞书文档里打一段字再自动删掉），
让电脑看起来一直有人在用；我一碰鼠标键盘它就自动让位，不会跟我抢。这是我本人自愿安装在自己电脑上的个人小工具。

工具放在这个公开的 GitHub 仓库里：https://github.com/syzhao326/keep-active

请帮我安装和配置好。如果你能直接在「终端」里执行命令，就帮我执行；如果不能，就把每一步
需要我在「终端」App 里运行的命令，清楚地一条条告诉我，让我自己复制粘贴。请一步步来，
每完成一步、等我确认后再继续，并且不要做与安装这个工具无关的其他操作。

步骤：

1) 一键安装。在终端运行：
   curl -fsSL https://raw.githubusercontent.com/syzhao326/keep-active/main/install.sh | bash

2) 授予「辅助功能」权限（这一步必须我本人在系统设置里点，你无法替我点）。运行：
   "$HOME/Library/Application Support/KeepActive/keepactive" start
   这会自动打开「系统设置 → 隐私与安全性 → 辅助功能」。请指导我：在列表里找到 keepactive，
   把它右边的开关打开；如果列表里没有它，就点列表下方的「＋」，把命令里提示的那个文件加进来，再打开开关。

3) 我把开关打开后，再运行一次同样的 start 命令，工具就在后台启动了。之后我可以关掉终端窗口。

4)（可选，验证飞书打字是否正常）让我先打开一个飞书文档、把光标点进正文里，然后运行：
   "$HOME/Library/Application Support/KeepActive/keepactive" test-feishu
   它会当着我的面打一段字、再自动删掉。确认打对了、也删干净了，就说明一切正常。

常用命令（以后直接用）：
   启动： keepactive start
   停止： keepactive stop
   查看状态： keepactive status

如果我想改自动输入的那段话，告诉我怎么编辑这个文件里的 feishuText 字段：
   ~/Library/Application Support/KeepActive/config.json
（改完后要先 keepactive stop 再 keepactive start 才生效。）
```

---

## 如果不想用 AI，也可以自己装

打开「终端」App（在「启动台」或「应用程序 → 实用工具」里），粘贴这一行回车：

```bash
curl -fsSL https://raw.githubusercontent.com/syzhao326/keep-active/main/install.sh | bash
```

装完后照着终端里打印的两步提示做即可。完整说明见仓库首页的 [README](README.md)。
