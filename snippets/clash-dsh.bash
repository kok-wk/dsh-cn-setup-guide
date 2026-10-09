# ~/.bashrc 追加片段：Clash + dsh 一站式快捷命令
# 用法：source snippets/clash-dsh.bash 或把内容追加到 ~/.bashrc
# 依赖：ss, gsettings (GNOME), curl；Clash 二进制与配置按你的路径修改

# ===== GNOME 系统代理开关（浏览器等遵循系统代理的应用立即生效） =====
clash_sysproxy_on() {
    gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1', '10.0.0.0/8', '192.168.0.0/16']" 2>/dev/null
    gsettings set org.gnome.system.proxy.http host '127.0.0.1' 2>/dev/null
    gsettings set org.gnome.system.proxy.http port 7890 2>/dev/null
    gsettings set org.gnome.system.proxy.https host '127.0.0.1' 2>/dev/null
    gsettings set org.gnome.system.proxy.https port 7890 2>/dev/null
    gsettings set org.gnome.system.proxy.socks host '127.0.0.1' 2>/dev/null
    gsettings set org.gnome.system.proxy.socks port 7891 2>/dev/null
    gsettings set org.gnome.system.proxy mode 'manual' 2>/dev/null
}

clash_sysproxy_off() {
    gsettings set org.gnome.system.proxy mode 'none' 2>/dev/null
}

# ===== Clash 快捷命令 =====
clashgo() {
    local CLASH_DIR="$HOME/clash"
    local BIN="$CLASH_DIR/clash-linux-amd64-v1.10.0"
    local CONF="$CLASH_DIR/config.yaml"   # 改成你的订阅配置文件名
    local LOG="$CLASH_DIR/clash.log"
    local PID="$CLASH_DIR/clash.pid"

    if [ ! -x "$BIN" ]; then
        echo "找不到可执行文件：$BIN"
        return 1
    fi
    if [ ! -f "$CONF" ]; then
        echo "找不到配置文件：$CONF"
        return 1
    fi

    if ss -ltn 2>/dev/null | grep -q ':7890'; then
        echo "Clash 已在运行（7890 端口已监听）"
        pgrep -f "$BIN" | head -1 > "$PID" 2>/dev/null
    else
        cd "$CLASH_DIR" || return 1
        nohup "$BIN" -f "$CONF" -d "$CLASH_DIR" >"$LOG" 2>&1 &
        echo $! > "$PID"
        cd - >/dev/null
        sleep 1
        if ! kill -0 "$(cat "$PID")" 2>/dev/null; then
            echo "Clash 启动失败，日志如下："
            tail -n 30 "$LOG"
            return 1
        fi
        echo "Clash 已启动，PID=$(cat "$PID")，日志：$LOG"
    fi

    export http_proxy="http://127.0.0.1:7890"
    export https_proxy="http://127.0.0.1:7890"
    export all_proxy="socks5://127.0.0.1:7891"
    export HTTP_PROXY="$http_proxy"
    export HTTPS_PROXY="$https_proxy"
    export ALL_PROXY="$all_proxy"
    export no_proxy="localhost,127.0.0.1,::1"
    export NO_PROXY="$no_proxy"

    # 系统代理（浏览器等）自动设为手动，无需再去网络设置里改
    clash_sysproxy_on

    echo "终端环境变量 + 系统代理均已设置。测试：curl -I https://www.google.com"
}

# 只取消当前终端的代理环境变量；Clash 进程与系统代理保持不动
clashoff() {
    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    echo "已取消当前终端的代理环境变量（Clash 与系统代理不受影响）"
}

# 彻底下线：停 Clash + 清环境变量 + 系统代理恢复直连
clashstop() {
    local CLASH_DIR="$HOME/clash"
    local PID="$CLASH_DIR/clash.pid"

    if [ -f "$PID" ] && kill -0 "$(cat "$PID")" 2>/dev/null; then
        kill "$(cat "$PID")" 2>/dev/null
        rm -f "$PID"
        echo "Clash 已停止"
    else
        pkill -f "$CLASH_DIR/clash-linux-amd64-v1.10.0" 2>/dev/null && echo "Clash 已停止" || echo "Clash 未运行"
    fi

    clash_sysproxy_off
    clashoff
}

# ===== dsh (DeepSeek Harness) =====
dshstop() {
    # 停掉占用 3080 端口的 dsh web 实例（按端口精确查找，不误伤其他程序）
    local pids
    pids=$(ss -ltnp 2>/dev/null | grep ':3080' | grep -oP 'pid=\K[0-9]+' | sort -u)
    if [ -n "$pids" ]; then
        echo "$pids" | xargs kill 2>/dev/null
        sleep 1
        if ss -ltn 2>/dev/null | grep -q ':3080'; then
            echo "$pids" | xargs kill -9 2>/dev/null
        fi
        echo "dsh web 已停止，3080 端口已释放"
    else
        echo "没有正在运行的 dsh web（3080 端口空闲）"
    fi
}
