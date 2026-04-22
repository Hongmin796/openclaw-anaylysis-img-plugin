#!/bin/bash
set -euo pipefail

# ── 插件配置（通过环境变量注入，不写入 openclaw.json）──────────────────
PLUGIN_NPM_NAME="${PLUGIN_NPM_NAME:-@hongmin204324/openclaw-image-analysis}"
PLUGIN_ID="openclaw-image-analysis"

DOUBAO_API_KEY="${DOUBAO_API_KEY:?请设置环境变量 DOUBAO_API_KEY}"
DOUBAO_MODEL="${DOUBAO_MODEL:-doubao-seed-2-0-pro-260215}"
OSS_REGION="${OSS_REGION:?请设置环境变量 OSS_REGION}"
OSS_ACCESS_KEY_ID="${OSS_ACCESS_KEY_ID:?请设置环境变量 OSS_ACCESS_KEY_ID}"
OSS_ACCESS_KEY_SECRET="${OSS_ACCESS_KEY_SECRET:?请设置环境变量 OSS_ACCESS_KEY_SECRET}"
OSS_BUCKET="${OSS_BUCKET:?请设置环境变量 OSS_BUCKET}"

# ── 1. 安装插件 ─────────────────────────────────────────────────────────
echo "[1/3] 安装插件: $PLUGIN_NPM_NAME"
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

# ── 2. 写入环境变量到 systemd drop-in ────────────────────────────────────
echo "[2/3] 注入环境变量到 Gateway 服务"
OVERRIDE_DIR="/etc/systemd/system/openclaw-gateway.service.d"
mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE_DIR/openclaw-image-analysis-env.conf" << EOF
[Service]
Environment="DOUBAO_API_KEY=$DOUBAO_API_KEY"
Environment="DOUBAO_MODEL=$DOUBAO_MODEL"
Environment="OSS_REGION=$OSS_REGION"
Environment="OSS_ACCESS_KEY_ID=$OSS_ACCESS_KEY_ID"
Environment="OSS_ACCESS_KEY_SECRET=$OSS_ACCESS_KEY_SECRET"
Environment="OSS_BUCKET=$OSS_BUCKET"
EOF
systemctl daemon-reload
echo "环境变量写入成功: $OVERRIDE_DIR/openclaw-image-analysis-env.conf"

# ── 3. 重启 Gateway 并验证 ────────────────────────────────────────────────
echo "[3/3] 重启 OpenClaw Gateway"
openclaw gateway restart
sleep 2
openclaw plugins inspect "$PLUGIN_ID"

echo ""
echo "✅ 插件安装并配置完成：$PLUGIN_NPM_NAME"
