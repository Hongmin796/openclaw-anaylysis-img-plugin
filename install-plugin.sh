#!/bin/bash
set -euo pipefail

# ── 插件配置（通过环境变量覆盖，避免明文写在脚本里）──────────────────
PLUGIN_PACKAGE="${PLUGIN_PACKAGE:-@hongmin204324/openclaw-image-analysis}"
PLUGIN_ID="image-analysis-plugin"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

DOUBAO_API_KEY="${DOUBAO_API_KEY:?请设置环境变量 DOUBAO_API_KEY}"
DOUBAO_MODEL="${DOUBAO_MODEL:-doubao-seed-2-0-pro-260215}"
OSS_REGION="${OSS_REGION:?请设置环境变量 OSS_REGION}"
OSS_ACCESS_KEY_ID="${OSS_ACCESS_KEY_ID:?请设置环境变量 OSS_ACCESS_KEY_ID}"
OSS_ACCESS_KEY_SECRET="${OSS_ACCESS_KEY_SECRET:?请设置环境变量 OSS_ACCESS_KEY_SECRET}"
OSS_BUCKET="${OSS_BUCKET:?请设置环境变量 OSS_BUCKET}"

# ── 1. 先写入插件配置（install 时 openclaw 会校验配置，必须先写）──────
echo "[1/4] 写入插件配置: $OPENCLAW_CONFIG"

mkdir -p "$(dirname "$OPENCLAW_CONFIG")"

node --input-type=module <<EOF
import fs from 'fs';

const configPath = '$OPENCLAW_CONFIG';

let config = {};
if (fs.existsSync(configPath)) {
  const raw = fs.readFileSync(configPath, 'utf8')
    .replace(/\/\/[^\n]*/g, '')
    .replace(/\/\*[\s\S]*?\*\//g, '')
    .replace(/,(\s*[}\]])/g, '\$1');
  try {
    config = JSON.parse(raw);
  } catch (e) {
    console.error('无法解析现有配置文件:', e.message);
    process.exit(1);
  }
}

config.plugins ??= {};
config.plugins.entries ??= {};
config.plugins.entries['$PLUGIN_ID'] = {
  enabled: true,
  config: {
    apiKey: '$DOUBAO_API_KEY',
    model: '$DOUBAO_MODEL',
    oss: {
      region: '$OSS_REGION',
      accessKeyId: '$OSS_ACCESS_KEY_ID',
      accessKeySecret: '$OSS_ACCESS_KEY_SECRET',
      bucket: '$OSS_BUCKET'
    }
  }
};

fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
console.log('配置写入成功');
EOF

# ── 2. 安装插件 ────────────────────────────────────────────────────────
echo "[2/4] 安装插件: $PLUGIN_PACKAGE"
openclaw plugins install "$PLUGIN_PACKAGE"

# ── 3. 重启 Gateway ────────────────────────────────────────────────────
echo "[3/4] 重启 OpenClaw Gateway"
openclaw gateway restart

# ── 4. 验证安装 ────────────────────────────────────────────────────────
echo "[4/4] 验证插件状态"
openclaw plugins inspect "$PLUGIN_ID"

echo ""
echo "✅ 插件安装并配置完成：$PLUGIN_PACKAGE"
