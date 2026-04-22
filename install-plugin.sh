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

jq \
  --arg id     "$PLUGIN_ID" \
  --arg apiKey "$DOUBAO_API_KEY" \
  --arg model  "$DOUBAO_MODEL" \
  --arg region "$OSS_REGION" \
  --arg keyId  "$OSS_ACCESS_KEY_ID" \
  --arg secret "$OSS_ACCESS_KEY_SECRET" \
  --arg bucket "$OSS_BUCKET" \
  '.plugins.entries[$id].config = {
     apiKey: $apiKey,
     model:  $model,
     oss: {
       region:          $region,
       accessKeyId:     $keyId,
       accessKeySecret: $secret,
       bucket:          $bucket
     }
   }' \
  "$OPENCLAW_CONFIG" > "$OPENCLAW_CONFIG.tmp" \
  && mv "$OPENCLAW_CONFIG.tmp" "$OPENCLAW_CONFIG"

echo "配置写入成功"

# ── 3. 重启 Gateway ────────────────────────────────────────────────────
echo "[3/4] 重启 OpenClaw Gateway"
openclaw gateway restart

# ── 4. 验证安装 ────────────────────────────────────────────────────────
echo "[4/4] 验证插件状态"
openclaw plugins inspect "$PLUGIN_ID"

echo ""
echo "✅ 插件安装并配置完成：$PLUGIN_NPM_NAME"
