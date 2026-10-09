#!/usr/bin/env bash
# dsh_doctor.sh —— DeepSeek Harness (dsh) 国内网络环境一键自检
# 检查：Clash 进程/端口、节点连通性、终端代理变量、npm/pnpm 代理配置、
#       NODE_OPTIONS 注入、dsh 安装状态、3080 端口占用
set -u

PASS=0; WARN=0; FAIL=0
ok()   { echo "  [OK]   $1"; PASS=$((PASS+1)); }
warn() { echo "  [WARN] $1"; WARN=$((WARN+1)); }
bad()  { echo "  [FAIL] $1"; FAIL=$((FAIL+1)); }

echo "== 1. Clash 代理进程与端口 =="
if pgrep -f 'clash' >/dev/null 2>&1; then
    ok "Clash 进程运行中 (PID: $(pgrep -f clash | head -1 | tr '\n' ' '))"
else
    bad "Clash 未运行 —— npm/npx 会卡死，请先启动 (clashgo)"
fi
if ss -ltn 2>/dev/null | grep -q ':7890'; then
    ok "HTTP 代理端口 7890 已监听"
else
    bad "端口 7890 未监听"
fi
if ss -ltn 2>/dev/null | grep -q ':7891'; then
    ok "SOCKS5 端口 7891 已监听"
else
    warn "端口 7891 未监听（SOCKS5 不可用，一般不影响 npm）"
fi

echo "== 2. npm registry 连通性 =="
code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 10 -x http://127.0.0.1:7890 https://registry.npmjs.org/ 2>/dev/null)
if [ "$code" = "200" ]; then
    ok "经代理访问 registry.npmjs.org: 200"
else
    bad "经代理访问 registry 失败 (code=${code:-超时}) —— 可能是代理节点失联，查 Clash 日志并换节点"
fi

echo "== 3. 当前终端代理环境变量 =="
if [ -n "${http_proxy:-}${HTTP_PROXY:-}" ]; then
    ok "http_proxy 已设置: ${http_proxy:-$HTTP_PROXY}"
else
    warn "当前终端未设置 http_proxy（运行 clashgo 或手动 export）"
fi

echo "== 4. NODE_OPTIONS 注入检查（IDE 扩展会破坏 npm 安装） =="
if [ -n "${NODE_OPTIONS:-}" ]; then
    bad "检测到 NODE_OPTIONS=$NODE_OPTIONS"
    echo "         → 大型 npm 安装会因 safe-delete shim 失败，先执行: unset NODE_OPTIONS NODE_PATH"
else
    ok "无 NODE_OPTIONS 注入"
fi

echo "== 5. npm 网络重试配置 =="
retries=$(npm config get fetch-retries 2>/dev/null)
if [ "${retries:-2}" -ge 5 ] 2>/dev/null; then
    ok "npm fetch-retries=$retries"
else
    warn "npm fetch-retries=${retries:-2} 偏低，建议: npm config set fetch-retries 10"
fi

echo "== 6. pnpm 代理配置（dsh plugin 依赖 pnpm） =="
if command -v pnpm >/dev/null 2>&1; then
    ok "pnpm 已安装: $(pnpm --version 2>/dev/null)"
    p=$(pnpm config get proxy 2>/dev/null)
    if [ "$p" != "undefined" ] && [ -n "$p" ] && [ "$p" != "null" ]; then
        ok "pnpm proxy=$p"
    else
        bad "pnpm 未配置代理（它不读 HTTP_PROXY 环境变量），执行:"
        echo "         pnpm config set proxy http://127.0.0.1:7890 --global"
        echo "         pnpm config set https-proxy http://127.0.0.1:7890 --global"
    fi
else
    warn "pnpm 未安装（安装插件时需要）: npm install -g pnpm"
fi

echo "== 7. dsh 安装状态 =="
if command -v dsh >/dev/null 2>&1; then
    ok "dsh 已安装: $(dsh --version 2>/dev/null | head -1) ($(command -v dsh))"
else
    bad "dsh 未安装: npm install -g @deepseek-ai/dsh"
fi

echo "== 8. dsh web 端口占用 =="
if ss -ltn 2>/dev/null | grep -q ':3080'; then
    pid=$(ss -ltnp 2>/dev/null | grep ':3080' | grep -oP 'pid=\K[0-9]+' | head -1)
    warn "3080 端口已被占用 (PID=${pid:-未知}) —— 已有 dsh web 实例，再启动会 EADDRINUSE"
else
    ok "3080 端口空闲"
fi

echo
echo "结果: $PASS 通过, $WARN 警告, $FAIL 失败"
[ "$FAIL" -eq 0 ] || exit 1
