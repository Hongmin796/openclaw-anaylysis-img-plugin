#!/bin/bash
set -euo pipefail

# ── 插件配置（通过环境变量注入，不写入 openclaw.json）──────────────────
PLUGIN_NPM_NAME="${PLUGIN_NPM_NAME:-@hongmin204324/openclaw-image-analysis}"
# 默认固定带 configSchema 的最低版本；勿仅用裸包名，否则在镜像/缓存下可能仍拿到 1.0.3 等旧包
# 覆盖示例：PLUGIN_NPM_SPEC='@hongmin204324/openclaw-image-analysis@1.0.8'
PLUGIN_NPM_SPEC="${PLUGIN_NPM_SPEC:-${PLUGIN_NPM_NAME}@1.0.7}"
PLUGIN_ID="openclaw-image-analysis"
# 旧 manifest 使用的 id，需一并从配置里移除，避免网关仍校验旧扩展
LEGACY_PLUGIN_ID="image-analysis-plugin"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$HOME/.openclaw/openclaw.json}"

DOUBAO_API_KEY="${DOUBAO_API_KEY:?请设置环境变量 DOUBAO_API_KEY}"
DOUBAO_MODEL="${DOUBAO_MODEL:-doubao-seed-2-0-pro-260215}"
OSS_REGION="${OSS_REGION:?请设置环境变量 OSS_REGION}"
OSS_ACCESS_KEY_ID="${OSS_ACCESS_KEY_ID:?请设置环境变量 OSS_ACCESS_KEY_ID}"
OSS_ACCESS_KEY_SECRET="${OSS_ACCESS_KEY_SECRET:?请设置环境变量 OSS_ACCESS_KEY_SECRET}"
OSS_BUCKET="${OSS_BUCKET:?请设置环境变量 OSS_BUCKET}"

# 打包容许指定 registry：国内镜像常滞后于官方，导致 ETARGET「找不到 1.0.x」
# 覆盖示例：NPM_REGISTRY=https://registry.npmmirror.com
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmjs.org/}"

# ── 1. 安装插件 ─────────────────────────────────────────────────────────
echo "[1/3] 安装插件: $PLUGIN_NPM_SPEC（registry: $NPM_REGISTRY）"

# 先清理 openclaw.json 中的过期条目（含 installs 与旧 id），避免校验旧包 manifest
if [ -f "$OPENCLAW_CONFIG" ]; then
  node -e "
const fs = require('fs');
const p = process.argv[1], id = process.argv[2], legacy = process.argv[3];
const cfg = JSON.parse(fs.readFileSync(p, 'utf8'));
function rmPlugin(pid) {
  if (cfg.plugins && cfg.plugins.entries) delete cfg.plugins.entries[pid];
  if (cfg.plugins && cfg.plugins.installs) delete cfg.plugins.installs[pid];
  if (cfg.plugins && Array.isArray(cfg.plugins.allow))
    cfg.plugins.allow = cfg.plugins.allow.filter(function(x) { return x !== pid; });
}
rmPlugin(id);
rmPlugin(legacy);
fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
" "$OPENCLAW_CONFIG" "$PLUGIN_ID" "$LEGACY_PLUGIN_ID"
  echo "    已清理 openclaw.json 中 ${PLUGIN_ID} / ${LEGACY_PLUGIN_ID} 的 entries、installs、allow"
fi

PLUGIN_DIR="$HOME/.openclaw/extensions/$PLUGIN_ID"
if [ -d "$PLUGIN_DIR" ]; then
  echo "    删除旧插件目录: $PLUGIN_DIR ..."
  rm -rf "$PLUGIN_DIR"
fi

TMP_DIR=$(mktemp -d)
echo "    下载 tgz 到 $TMP_DIR ..."
if command -v npm >/dev/null 2>&1; then
  REG_VER="$(npm view "$PLUGIN_NPM_NAME" version --registry="$NPM_REGISTRY" 2>/dev/null || true)"
  if [ -n "$REG_VER" ]; then
    echo "    当前 registry 上 ${PLUGIN_NPM_NAME} 的 latest 版本: $REG_VER"
  fi
fi
npm pack "$PLUGIN_NPM_SPEC" --pack-destination "$TMP_DIR" --quiet --registry="$NPM_REGISTRY"
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
