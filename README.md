# DeepSeek Harness (dsh) 国内安装与排障实战指南

> **🤖 For AI Agents / AI 读者请先看这里**
> 本仓库遵循 **AI-first 文档约定**：AI 代理请优先阅读 [`AI-README.md`](AI-README.md)（入口 + 文件地图 + 知识浓缩，无需通读本篇即可行动）。
> 该约定（AI 为 AI 写文档）于 2026-10-09 在本仓库首次公开记录，此处为其源头。详见 [AI-README.md 末节](AI-README.md#ai-first-文档约定本仓库为首创记录源)。

> 在中国大陆 Linux 环境下安装 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)（`npx @deepseek-ai/dsh web`）的完整踩坑记录。
> 一次安装踩了 **7 个坑**：代理未启动、IDE 扩展注入破坏 npm、代理节点上游失联、网络重试缺失、pnpm 代理失效、端口冲突、系统代理需要手动设置——本文给出每一个的定位过程与解法。

## 环境背景

| 项目 | 值 |
|---|---|
| 系统 | Ubuntu 26.04 (x86_64) |
| Node / npm | v22.22.1 / 9.2.0 |
| 代理 | Clash v1.10.0（付费机场订阅），HTTP `127.0.0.1:7890`，SOCKS5 `127.0.0.1:7891` |
| dsh 版本 | `@deepseek-ai/dsh@0.2.0-rc.2`（543 个依赖包） |

## 快速结论（TL;DR）

```bash
# 0. 启动代理（终端 + 系统代理一次到位，见 snippets/clash-dsh.bash）
clashgo

# 1. 清除 IDE 注入的 NODE_OPTIONS（关键！见坑 2）
unset NODE_OPTIONS NODE_PATH

# 2. 全局安装（比 npx 稳，见坑 5）
npm config set fetch-retries 10
npm install -g @deepseek-ai/dsh pnpm

# 3. 给 pnpm 显式配置代理（见坑 6）
pnpm config set proxy http://127.0.0.1:7890 --global
pnpm config set https-proxy http://127.0.0.1:7890 --global

# 4. 启动
dsh web

# 5. 安装插件市场（可选）
dsh plugin --profile web add dshmarket
dshstop && dsh web   # 重启生效
```

---

## 坑 1：`npx` 长时间无输出卡死 —— 代理根本没启动

**现象**：`npx @deepseek-ai/dsh web` 长时间零输出；`npm ping`、`curl https://registry.npmjs.org/` 全部超时。

**定位**：

```bash
curl -sS -o /dev/null -w "%{http_code}\n" --max-time 10 https://registry.npmjs.org/
# 超时 → 网络问题，不是 npm 问题
ss -ltn | grep 7890   # 空 → Clash 没在运行
```

**解法**：先启动 Clash，并导出代理环境变量：

```bash
export http_proxy="http://127.0.0.1:7890"
export https_proxy="http://127.0.0.1:7890"
export all_proxy="socks5://127.0.0.1:7891"
export no_proxy="localhost,127.0.0.1,::1"
```

> **经验**：npm/npx 卡住时，先用 `curl` 直接测 registry，再 `ss -ltn` 查代理端口，30 秒内就能分清「网络问题」还是「包管理器问题」。

## 坑 2：VS Code 扩展注入的 `NODE_OPTIONS` 直接破坏 npm 安装 ⚠️

**现象**：npm 下载中途失败，日志出现：

```
npm WARN cleanup Failed to remove some directories
Error: [safe-delete][SAFE_DELETE_BULK_CONFIRM_REQUIRED]
  {"count":10005,"threshold":500,...}
    at checkBulkDeleteGuard (.../tencent-cloud.coding-copilot-*/out/vendor/shim/node-safe-delete-shim.cjs:404:19)
```

**根因**：VS Code 的腾讯云 CodeBuddy 扩展通过环境变量向**所有 node 子进程**注入了安全删除拦截器：

```
NODE_OPTIONS=--require=".../coding-copilot-*/out/vendor/shim/node-language-shim.cjs"
```

npm 安装大包时需要批量移动/删除上万个文件，超过该 shim 的阈值（500）即被拒绝，安装直接失败。**只要在 VS Code 集成终端里跑 npm/npx，就会中招。**

**定位**：

```bash
env | grep NODE_OPTIONS   # 有值即中招
```

**解法**：

```bash
unset NODE_OPTIONS NODE_PATH   # 再运行 npm/npx
```

一劳永逸的做法：大型安装用系统自带终端（GNOME Terminal 等）执行，或在 VS Code 里临时禁用该扩展。

> **经验**：在 IDE 集成终端里遇到诡异的包管理器故障，先 `env | grep -i node` 检查注入。

## 坑 3：代理节点上游失联 —— 连接建立却永无响应

**现象**：代理已开，`npm ping` 能通，但下载中途 7 个 TCP 连接全部挂死，无任何流量；随后 `ECONNRESET` 失败。

**定位**：看 Clash 日志（本例 `~/clash/clash.log`）：

```
level=warning msg="[TCP] dial <代理组名> ... to registry.npmjs.org:443 error:
  <你的订阅上游域名>:<端口> connect error: dial tcp4 <上游IP>:<端口>: i/o timeout"
```

上游服务器失联，但客户端连接仍被 Clash 接受并挂起——表现为「卡住」而非「报错」。

**解法**：通过 Clash RESTful API（默认 `127.0.0.1:9090`）切换节点：

```bash
# 逐个测节点延迟
for n in US-Dedicated-B1-2 JP-Dedicated-B1-1 JP-Dedicated-B1-2; do
  curl -s "http://127.0.0.1:9090/proxies/$n/delay?timeout=3000&url=http://www.gstatic.com/generate_204"
done

# 切换 Developer 组到最快节点
curl -X PUT -H 'Content-Type: application/json' \
  -d '{"name":"JP-Dedicated-B1-2"}' \
  http://127.0.0.1:9090/proxies/Developer
```

切换后单包下载从 **15s+ 恢复到 0.5~1.7s**。

> **经验**：「连接建立但零流量」≈ 上游节点挂了。先查 Clash 日志里的 `i/o timeout`，再用 API 换节点，比反复重跑安装快得多。

## 坑 4：npm 默认网络重试太少，代理抖动一次就全盘失败

**解法**：加环境变量或 npm config：

```bash
npm config set fetch-retries 10
npm config set fetch-retry-maxtimeout 120000
npm config set fetch-timeout 600000
```

dsh 有 500+ 依赖，代理链路长，**重试配置是刚需**。

## 坑 5：`npx` vs 全局安装 —— 大包请用全局安装

**现象**：`npx` 每次都解压到临时目录 `~/.npm/_npx/<hash>`，失败后残留 **477MB** 垃圾；且 npx 的清理逻辑更容易被坑 2 的 shim 干扰。

**解法**：

```bash
npm install -g @deepseek-ai/dsh   # 装到 ~/.npm-global（npmrc 已设 prefix）
dsh web                           # 以后直接用，秒启动
# 清理 npx 残留
rm -rf ~/.npm/_npx/*
```

> **经验**：依赖 500+ 的 CLI 工具，`npm i -g` 一次到位；`npx` 适合小工具。

## 坑 6：`dsh plugin` 需要 pnpm，而 pnpm 不读 `HTTP_PROXY` 环境变量

**现象**：`dsh plugin --profile web add dshmarket` 报 `pnpm was not found`；装好 pnpm 后又卡死——`pnpm add` 150 秒零输出，Clash 日志里**根本没有** pnpm 的请求。

**根因**：pnpm 12 的网络层不使用 `HTTP_PROXY`/`HTTPS_PROXY` 环境变量，直连 registry 超时。

**解法**：给 pnpm 显式写配置：

```bash
pnpm config set proxy http://127.0.0.1:7890 --global
pnpm config set https-proxy http://127.0.0.1:7890 --global
```

之后 `dsh plugin --profile web add dshmarket` **3.8 秒**完成（装的是 `dshmarket@1.66.x`，插件市场入口：Settings → Plugin Market）。

> **经验**：`npm` 走了代理不代表 `pnpm`/`yarn` 也走。三者代理配置互相独立，pnpm 必须 `pnpm config set`。

## 坑 7：`EADDRINUSE 127.0.0.1:3080` —— 旧实例还在后台

**现象**：再次运行 `dsh web` 报 `listen EADDRINUSE`，且 webserver 是 required 插件，它失败后其余 9 个依赖插件全部无法激活。

**根因**：之前用 `nohup ... &` 启动的实例还在运行；或终端直接点 X 关闭，进程变孤儿继续占端口。

**解法**（已封装为 `dshstop`，见 snippets）：

```bash
# 精确找到占用 3080 的 PID 并终止（只杀 dsh，不误伤别的程序）
ss -ltnp | grep ':3080' | grep -oP 'pid=\K[0-9]+' | xargs -r kill
```

> **经验**：`dsh web` 是前台进程，正常退出用 `Ctrl+C`。用 `pkill -f dsh` 太粗暴，按端口找 PID 最稳。

## 坑 8（附带）：GNOME 系统代理每次都要手动设置？

浏览器遵循 GNOME 系统代理（gsettings），不读 shell 环境变量。以前每次开代理都要去「设置 → 网络 → 网络代理 → 手动」点一遍。

**解法**：把 `gsettings` 调用写进 `clashgo`/`clashstop` 函数，一条命令同时管理「终端环境变量 + 系统代理」：

```bash
# 开：clashgo 内部执行
gsettings set org.gnome.system.proxy.http  host '127.0.0.1'
gsettings set org.gnome.system.proxy.http  port 7890
gsettings set org.gnome.system.proxy.https host '127.0.0.1'
gsettings set org.gnome.system.proxy.https port 7890
gsettings set org.gnome.system.proxy.socks host '127.0.0.1'
gsettings set org.gnome.system.proxy.socks port 7891
gsettings set org.gnome.system.proxy mode 'manual'

# 关（clashstop 内部执行）
gsettings set org.gnome.system.proxy mode 'none'
```

完整可用的 `clashgo` / `clashoff` / `clashstop` / `dshstop` 函数见 [`snippets/clash-dsh.bash`](snippets/clash-dsh.bash)。

---

## 一键自检脚本

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/kok-wk/dsh-cn-setup-guide/main/scripts/dsh_doctor.sh)
```

逐项检查：Clash 进程与端口、当前节点、终端代理变量、npm/pnpm 代理配置、`NODE_OPTIONS` 注入、3080 端口占用。（脚本内容见 [`scripts/dsh_doctor.sh`](scripts/dsh_doctor.sh)）

## 速查表

| 症状 | 根因 | 解法 |
|---|---|---|
| npx 零输出卡死 | 代理未启动 / 节点失联 | 启动 Clash；查日志换节点 |
| `SAFE_DELETE_BULK_CONFIRM_REQUIRED` | IDE 扩展注入 NODE_OPTIONS | `unset NODE_OPTIONS` |
| `ECONNRESET` / 连接挂死无流量 | 代理节点上游失联 | Clash API 换节点 + npm 加重试 |
| `pnpm was not found` | dsh plugin 依赖 pnpm | `npm i -g pnpm` |
| pnpm 卡死零输出 | pnpm 不读代理环境变量 | `pnpm config set proxy` |
| `EADDRINUSE :3080` | 旧实例占用端口 | 按端口找 PID kill（`dshstop`） |
| 浏览器不走代理 | 只设了终端变量 | `gsettings` 设系统代理（`clashgo` 已集成） |

## 相关链接

- [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness)
- [dsh-market 插件市场](https://github.com/dsh-market/dsh-market)
- [awesome-dsh-plugin 插件注册表](https://github.com/awesome-dsh-plugin)

## License

[MIT](LICENSE)
