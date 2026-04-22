#!/bin/bash
set -euo pipefail

# ── 插件配置（通过环境变量注入，不写入 openclaw.json）──────────────────
PLUGIN_NPM_NAME="${PLUGIN_NPM_NAME:-@hongmin204324/openclaw-image-analysis}"
# 默认固定带 configSchema 的最低版本；勿仅用裸包名，否则在镜像/缓存下可能仍拿到 1.0.3 等旧包
# 覆盖示例：PLUGIN_NPM_SPEC='@hongmin204324/openclaw-image-analysis@1.0.8'
PLUGIN_NPM_SPEC="${PLUGIN_NPM_SPEC:-${PLUGIN_NPM_NAME}@1.0.9}"
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
// 旧版安装失败时可能以 npm scoped 名写入 entries（与 manifest id 不一致）
rmPlugin('@hongmin204324/openclaw-image-analysis');
fs.writeFileSync(p, JSON.stringify(cfg, null, 2));
" "$OPENCLAW_CONFIG" "$PLUGIN_ID" "$LEGACY_PLUGIN_ID"
  echo "    已清理 openclaw.json 中 ${PLUGIN_ID} / ${LEGACY_PLUGIN_ID} 的 entries、installs、allow"
fi

PLUGIN_DIR="$HOME/.openclaw/extensions/$PLUGIN_ID"
if [ -d "$PLUGIN_DIR" ]; then
  echo "    删除旧插件目录: $PLUGIN_DIR ..."
  rm -rf "$PLUGIN_DIR"
fi

# OpenClaw 会扫描 ~/.openclaw/extensions 下每个子目录并读取 openclaw.plugin.json。
# 若只从 openclaw.json 删掉 legacy 条目、磁盘上仍保留旧目录，旧包无 configSchema 会导致整体验证失败。
LEGACY_EXT_DIR="$HOME/.openclaw/extensions/$LEGACY_PLUGIN_ID"
if [ -d "$LEGACY_EXT_DIR" ]; then
  echo "    删除遗留扩展目录: $LEGACY_EXT_DIR ..."
  rm -rf "$LEGACY_EXT_DIR"
fi

# 若历史上 manifest 未通过校验，OpenClaw 会用 npm scoped 包名落盘为哈希目录名（见 encodePluginInstallDirName），
# 与 manifest 中的 id（openclaw-image-analysis）不同，仅删上一段 PLUGIN_DIR 删不到它，会导致 doctor 一直报 configSchema。
EXT_BASE="${HOME}/.openclaw/extensions"
shopt -s nullglob
for d in "${EXT_BASE}"/@hongmin204324-openclaw-image-analysis-*; do
  if [ -d "$d" ]; then
    echo "    删除旧 scoped 哈希扩展目录: $d ..."
    rm -rf "$d"
  fi
done
shopt -u nullglob

# 网关会扫描 extensions 与 plugins.load.paths：任一 openclaw.plugin.json 缺少合法 configSchema 都会导致「整表配置无效」、进而无法 install。
# 将不合规目录重命名为含 .disabled（OpenClaw 会忽略该目录名），避免第三方旧包阻塞安装。
echo "    扫描并隔离 manifest 缺少 configSchema 的扩展目录…"
OPENCLAW_CONFIG_PATH="$OPENCLAW_CONFIG" EXTENSIONS_ROOT="${HOME}/.openclaw/extensions" node <<'NODE'
const fs = require("fs");
const path = require("path");
const os = require("os");

const home = os.homedir();
const extRoot = process.env.EXTENSIONS_ROOT || path.join(home, ".openclaw", "extensions");
const cfgPath = process.env.OPENCLAW_CONFIG_PATH || "";

function badConfigSchema(cs) {
  return cs === undefined || cs === null || typeof cs !== "object" || Array.isArray(cs);
}

function shouldSkipDirName(name) {
  const low = String(name).toLowerCase();
  return low.endsWith(".bak") || low.includes(".backup-") || low.includes(".disabled");
}

function quarantine(dir, tag) {
  const parent = path.dirname(dir);
  const base = path.basename(dir);
  const target = path.join(parent, `${base}.disabled-openclaw-${Date.now()}-${tag}`);
  fs.renameSync(dir, target);
  console.log(`    已隔离: ${dir} -> ${target}`);
}

function scanPluginRoot(dir) {
  if (!dir) return;
  let st;
  try {
    st = fs.statSync(dir);
  } catch {
    return;
  }
  if (!st.isDirectory()) return;
  const mf = path.join(dir, "openclaw.plugin.json");
  if (!fs.existsSync(mf)) return;
  let raw;
  try {
    raw = JSON.parse(fs.readFileSync(mf, "utf8"));
  } catch {
    quarantine(dir, "bad-json");
    return;
  }
  if (badConfigSchema(raw.configSchema)) quarantine(dir, "no-configSchema");
}

try {
  const entries = fs.readdirSync(extRoot, { withFileTypes: true });
  for (const ent of entries) {
    if (!ent.isDirectory()) continue;
    if (shouldSkipDirName(ent.name)) continue;
    scanPluginRoot(path.join(extRoot, ent.name));
  }
} catch (e) {
  if (e && e.code !== "ENOENT") console.warn("    扫描 extensions 失败:", String(e));
}

if (cfgPath && fs.existsSync(cfgPath)) {
  try {
    const cfg = JSON.parse(fs.readFileSync(cfgPath, "utf8"));
    const paths = cfg?.plugins?.load?.paths;
    if (Array.isArray(paths)) {
      for (const p of paths) {
        if (typeof p !== "string" || !p.trim()) continue;
        let resolved = p.trim();
        if (resolved.startsWith("~/")) resolved = path.join(home, resolved.slice(2));
        else if (resolved === "~") resolved = home;
        else if (resolved.startsWith("~")) resolved = path.join(home, resolved.slice(1));
        scanPluginRoot(resolved);
      }
    }
  } catch (e) {
    console.warn("    读取 plugins.load.paths 失败:", String(e));
  }
}
NODE

if command -v openclaw >/dev/null 2>&1; then
  echo "    尝试 openclaw doctor --fix --yes（清理过时配置项）…"
  openclaw doctor --fix --yes 2>/dev/null || true
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
# root：系统级 unit；普通用户：用户级 unit（与 doctor 安装的 ~/.config/systemd/user/ 一致）
echo "[2/3] 注入环境变量到 Gateway 服务（systemd drop-in）"
ENV_DROPIN="openclaw-image-analysis-env.conf"
if [ "$(id -u)" -eq 0 ]; then
  OVERRIDE_DIR="/etc/systemd/system/openclaw-gateway.service.d"
  echo "    使用系统级目录: $OVERRIDE_DIR"
else
  OVERRIDE_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/openclaw-gateway.service.d"
  echo "    当前非 root：使用用户级目录: $OVERRIDE_DIR"
fi
mkdir -p "$OVERRIDE_DIR"
cat > "$OVERRIDE_DIR/$ENV_DROPIN" << EOF
[Service]
Environment="DOUBAO_API_KEY=$DOUBAO_API_KEY"
Environment="DOUBAO_MODEL=$DOUBAO_MODEL"
Environment="OSS_REGION=$OSS_REGION"
Environment="OSS_ACCESS_KEY_ID=$OSS_ACCESS_KEY_ID"
Environment="OSS_ACCESS_KEY_SECRET=$OSS_ACCESS_KEY_SECRET"
Environment="OSS_BUCKET=$OSS_BUCKET"
EOF
if [ "$(id -u)" -eq 0 ]; then
  systemctl daemon-reload 2>/dev/null || true
else
  systemctl --user daemon-reload 2>/dev/null || echo "    （提示）若未使用 systemd --user 管理 Gateway，可改用手动 export 或写入 openclaw 支持的环境配置。"
fi
echo "环境变量写入成功: $OVERRIDE_DIR/$ENV_DROPIN"

# ── 3. 重启 Gateway 并验证 ────────────────────────────────────────────────
echo "[3/3] 重启 OpenClaw Gateway"
openclaw gateway restart
sleep 2
openclaw plugins inspect "$PLUGIN_ID"

echo ""
echo "✅ 插件安装并配置完成：$PLUGIN_NPM_NAME"
