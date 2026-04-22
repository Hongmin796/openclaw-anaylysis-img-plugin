#!/bin/bash
set -euo pipefail

# ── 插件配置（通过环境变量覆盖，避免明文写在脚本里）──────────────────
PLUGIN_NPM_NAME="${PLUGIN_NPM_NAME:-@hongmin204324/openclaw-image-analysis}"
PLUGIN_ID="image-analysis-plugin"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

DOUBAO_API_KEY="${DOUBAO_API_KEY:?请设置环境变量 DOUBAO_API_KEY}"
DOUBAO_MODEL="${DOUBAO_MODEL:-doubao-seed-2-0-pro-260215}"
OSS_REGION="${OSS_REGION:?请设置环境变量 OSS_REGION}"
OSS_ACCESS_KEY_ID="${OSS_ACCESS_KEY_ID:?请设置环境变量 OSS_ACCESS_KEY_ID}"
OSS_ACCESS_KEY_SECRET="${OSS_ACCESS_KEY_SECRET:?请设置环境变量 OSS_ACCESS_KEY_SECRET}"
OSS_BUCKET="${OSS_BUCKET:?请设置环境变量 OSS_BUCKET}"

# ── 1. 安装插件（从 npm 下载 tgz，绕过 ClawHub）─────────────────────
echo "[1/4] 安装插件: $PLUGIN_NPM_NAME"
PLUGIN_DIR="$HOME/.openclaw/extensions/$PLUGIN_ID"
if [ -d "$PLUGIN_DIR" ]; then
  echo "    检测到旧版本，删除 $PLUGIN_DIR ..."
  rm -rf "$PLUGIN_DIR"
fi
TMP_DIR=$(mktemp -d)
echo "    下载 tgz 到 $TMP_DIR ..."
npm pack "$PLUGIN_NPM_NAME" --pack-destination "$TMP_DIR" --quiet
TGZ_FILE=$(ls "$TMP_DIR"/*.tgz | head -1)
echo "    从本地安装: $TGZ_FILE"
openclaw plugins install "$TGZ_FILE"
rm -rf "$TMP_DIR"

# ── 2. 写入插件配置 ────────────────────────────────────────────────────
echo "[2/4] 更新配置文件: $OPENCLAW_CONFIG"

mkdir -p "$(dirname "$OPENCLAW_CONFIG")"

# 使用 'EOF'（带引号）禁止 bash 转义，变量通过 process.env 传入
OPENCLAW_CONFIG="$OPENCLAW_CONFIG" \
PLUGIN_ID="$PLUGIN_ID" \
DOUBAO_API_KEY="$DOUBAO_API_KEY" \
DOUBAO_MODEL="$DOUBAO_MODEL" \
OSS_REGION="$OSS_REGION" \
OSS_ACCESS_KEY_ID="$OSS_ACCESS_KEY_ID" \
OSS_ACCESS_KEY_SECRET="$OSS_ACCESS_KEY_SECRET" \
OSS_BUCKET="$OSS_BUCKET" \
node --input-type=module <<'EOF'
import fs from 'fs';

const configPath   = process.env.OPENCLAW_CONFIG;
const pluginId     = process.env.PLUGIN_ID;
const apiKey       = process.env.DOUBAO_API_KEY;
const model        = process.env.DOUBAO_MODEL;
const ossRegion    = process.env.OSS_REGION;
const ossKeyId     = process.env.OSS_ACCESS_KEY_ID;
const ossKeySecret = process.env.OSS_ACCESS_KEY_SECRET;
const ossBucket    = process.env.OSS_BUCKET;

let config = {};
if (fs.existsSync(configPath)) {
  let raw = fs.readFileSync(configPath, 'utf8');

  // 去除注释
  raw = raw.replace(/\/\/[^\n]*/g, '').replace(/\/\*[\s\S]*?\*\//g, '');

  // 逐字符扫描，转义字符串内的裸控制字符（JSON5 允许但标准 JSON 不允许）
  let result = '';
  let inStr = false;
  let esc = false;
  for (let i = 0; i < raw.length; i++) {
    const c = raw[i];
    const code = raw.charCodeAt(i);
    if (esc)                    { result += c; esc = false; continue; }
    if (c === '\\' && inStr)    { result += c; esc = true;  continue; }
    if (c === '"')              { inStr = !inStr; result += c; continue; }
    if (inStr && code < 32) {
      if      (code === 10) result += '\\n';
      else if (code === 13) result += '\\r';
      else if (code === 9)  result += '\\t';
      continue;
    }
    result += c;
  }
  raw = result.replace(/,(\s*[}\]])/g, '$1');

  try {
    config = JSON.parse(raw);
  } catch (e) {
    console.error('无法解析现有配置文件:', e.message);
    process.exit(1);
  }
}

config.plugins ??= {};
config.plugins.entries ??= {};
config.plugins.entries[pluginId] = {
  enabled: true,
  config: {
    apiKey,
    model,
    oss: {
      region:          ossRegion,
      accessKeyId:     ossKeyId,
      accessKeySecret: ossKeySecret,
      bucket:          ossBucket,
    },
  },
};

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('配置写入成功');
EOF

# ── 3. 重启 Gateway ────────────────────────────────────────────────────
echo "[3/4] 重启 OpenClaw Gateway"
openclaw gateway restart

# ── 4. 验证安装 ────────────────────────────────────────────────────────
echo "[4/4] 验证插件状态"
openclaw plugins inspect "$PLUGIN_ID"

echo ""
echo "✅ 插件安装并配置完成：$PLUGIN_NPM_NAME"
