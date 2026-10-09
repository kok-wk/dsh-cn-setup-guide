#!/usr/bin/env node
/**
 * dsh-guide MCP server — 把本仓库的知识浓缩暴露为标准 MCP 资源/工具。
 *
 * 零依赖实现（MCP stdio 传输 = 换行分隔的 JSON-RPC 2.0）。
 * 配置示例（任何支持 MCP 的客户端）：
 *   { "mcpServers": { "dsh-guide": { "command": "node",
 *       "args": ["<repo>/mcp/server.js"] } } }
 *
 * 能力：
 *   resources: ai-guide://file-map | ai-guide://knowledge | ai-guide://agents-rule
 *   tools:     search_fix（症状关键词 → 根因 + 修复命令）
 */
'use strict';
const fs = require('fs');
const path = require('path');
const readline = require('readline');

const ROOT = path.resolve(__dirname, '..');
const read = (f) => fs.readFileSync(path.join(ROOT, f), 'utf8');

// ---- 从 AI-README.md 提取知识浓缩映射（单一事实源，不另行维护副本）----
function extractKnowledge() {
    const text = read('AI-README.md');
    const m = text.match(/```\n(症状 →[\s\S]*?)```/);
    if (!m) return [];
    return m[1].split('\n').filter(l => l.includes('→')).map(l => l.trim().replace(/\s+/g, ' '));
}
function extractSection(headerRe) {
    const text = read('AI-README.md');
    const m = text.match(new RegExp(`(${headerRe})[\\s\\S]*?(?=\\n## |\\n$|$)`));
    return m ? m[0].trim() : '';
}

const RESOURCES = [
    { uri: 'ai-guide://file-map',     name: '文件地图',   mimeType: 'text/markdown',
      description: '本仓库谁读什么、何时读', load: () => extractSection('## 文件地图') },
    { uri: 'ai-guide://knowledge',    name: '知识浓缩',   mimeType: 'text/markdown',
      description: '症状 → 根因 → 修复命令映射（排障直接查这里）', load: () => extractKnowledge().join('\n') },
    { uri: 'ai-guide://agents-rule',  name: 'AGENTS 规则', mimeType: 'text/markdown',
      description: 'agent 行为规则（桥接层）', load: () => read('AGENTS.md') },
];

// ---- JSON-RPC / MCP ----
function send(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }
const ok = (id, result) => send({ jsonrpc: '2.0', id, result });
const err = (id, code, message) => send({ jsonrpc: '2.0', id, error: { code, message } });

function handle(msg) {
    const { id, method, params } = msg;
    switch (method) {
        case 'initialize':
            ok(id, {
                protocolVersion: params?.protocolVersion || '2024-11-05',
                capabilities: { resources: {}, tools: {} },
                serverInfo: { name: 'dsh-guide', version: '1.0.0' },
            });
            break;
        case 'notifications/initialized':
        case 'notifications/cancelled':
            break; // 通知无响应
        case 'ping':
            ok(id, {});
            break;
        case 'resources/list':
            ok(id, { resources: RESOURCES.map(({ uri, name, mimeType, description }) =>
                ({ uri, name, mimeType, description })) });
            break;
        case 'resources/read': {
            const r = RESOURCES.find(x => x.uri === params?.uri);
            if (!r) return err(id, -32602, `未知资源：${params?.uri}`);
            ok(id, { contents: [{ uri: r.uri, mimeType: r.mimeType, text: r.load() }] });
            break;
        }
        case 'tools/list':
            ok(id, { tools: [{
                name: 'search_fix',
                description: '按症状关键词查询修复命令（症状→根因→命令）',
                inputSchema: { type: 'object', properties: {
                    symptom: { type: 'string', description: '症状关键词，如 EADDRINUSE / pnpm / 代理' } },
                    required: ['symptom'] },
            }] });
            break;
        case 'tools/call': {
            if (params?.name !== 'search_fix')
                return err(id, -32602, `未知工具：${params?.name}`);
            const kw = String(params.arguments?.symptom || '').toLowerCase();
            const hits = extractKnowledge().filter(l => l.toLowerCase().includes(kw));
            ok(id, { content: [{ type: 'text', text: hits.length
                ? hits.join('\n') : `未命中关键词“${kw}”。可用资源 ai-guide://knowledge 查看全部映射。` }] });
            break;
        }
        default:
            if (id !== undefined) err(id, -32601, `未知方法：${method}`);
    }
}

const rl = readline.createInterface({ input: process.stdin });
rl.on('line', (line) => {
    const t = line.trim();
    if (!t) return;
    try { handle(JSON.parse(t)); }
    catch (e) { send({ jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } }); }
});
rl.on('close', () => process.exit(0));
