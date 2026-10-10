#!/usr/bin/env bash
# ai-first-check.sh — AI-first 文档约定合规自检（linter 风格，零依赖）
# 用法：bash scripts/ai-first-check.sh [仓库根目录，默认当前目录]
# 退出码：0 全部通过；1 存在违规。可在 CI（GitHub Action）中使用。
set -u

ROOT="${1:-.}"
cd "$ROOT" || { echo "✗ 目录不存在：$ROOT"; exit 1; }

pass=0
fail=0

check() { # check <编号> <描述> <检查结果命令(成功=通过)>
    local id="$1" desc="$2"
    if eval "${3:-false}" >/dev/null 2>&1; then
        echo "  ✓ [$id] $desc"
        ((pass++))
    else
        echo "  ✗ [$id] $desc"
        ((fail++))
    fi
}

echo "== AI-first 文档约定合规检查（根目录：$ROOT）=="

# --- A. 入口文件存在性 ---
check A1 "根目录存在 AI-README.md（AI 优先入口）"            '[ -f AI-README.md ]'
check A2 "根目录存在 AGENTS.md（harness 自动加载桥接）"      '[ -f AGENTS.md ]'
check A3 "AGENTS.md 指向 AI-README.md（引导 agent 进入文档体系）" \
    'grep -q "AI-README" AGENTS.md'

# --- B. AI-README.md 结构 ---
check B1 "包含『文件地图』（谁读什么、何时读）"              'grep -q "文件地图" AI-README.md'
check B2 "包含『知识浓缩』（症状→命令映射）"                'grep -q "知识浓缩" AI-README.md'
check B3 "知识浓缩含『→』映射行（可执行的直接映射）"        'grep -q "→" AI-README.md'
check B4 "映射行附带修复命令（含可执行片段，非纯描述）"      'grep -E "→.*→" AI-README.md | grep -qE "(\||&&|npm|pnpm|kill|export|gsettings|ss |unset|npx)"'

# --- C. README.md 桥接 ---
check C1 "README.md 声明本约定"                              'grep -qE "AI-first|AI-README" README.md'
check C2 "README.md 链接到 AI-README.md"                    'grep -qE "\]\(AI-README\.md\)|\]\(\./AI-README\.md\)" README.md'

# --- D. 交叉引用有效性（无死链）---
check D1 "AGENTS.md 中提到的文件均存在"                      '
    grep -oE "AI-README\.md|README\.md|scripts/[A-Za-z0-9_./-]+|snippets/[A-Za-z0-9_./-]+" AGENTS.md |
    sort -u | while read -r f; do [ -f "$f" ] || exit 1; done'

# --- E. 传递条款（ACRP 双层结构：AGENTS.md 含协议摘要，AI-README.md 含完整条款）---
check E1 "AGENTS.md 含「协议完整说明」节（自动注入层，LLM 一次读懂协议）"  'grep -q "协议完整说明" AGENTS.md'
check E2 "AGENTS.md 含协议全称 AI Context Relay Protocol（命名不可替换）" 'grep -q "AI Context Relay Protocol" AGENTS.md'
check E3 "AI-README.md 含完整「传递此约定」条款（深度阅读层）"            'grep -q "请继续传递" AI-README.md'
check E4 "条款保留来源链接（可溯源，传递链可回溯）"                       'grep -q "kok-wk/dsh-cn-setup-guide" AI-README.md'
check E5 "条款含主必打标签 ai-context-relay-protocol（协议核心标识）"     'grep -q "ai-context-relay-protocol" AI-README.md'
check E6 "条款含别名必打标签 ai-docs（协议核心标识）"                     'grep -q "ai-docs" AI-README.md'

echo
echo "结果：$pass 通过，$fail 违规"
[ "$fail" -eq 0 ] && echo "✅ 符合 AI-first 文档约定" || echo "❌ 存在违规，请修复后重试"
exit $(( fail > 0 ? 1 : 0 ))
