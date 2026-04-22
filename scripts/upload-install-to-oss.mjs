/**
 * 将仓库根目录的 install-plugin.sh 上传到 OSS：scripts/install-plugin.sh
 * 需设置环境变量：OSS_REGION、OSS_ACCESS_KEY_ID、OSS_ACCESS_KEY_SECRET、OSS_BUCKET
 * 用法：node scripts/upload-install-to-oss.mjs
 */
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const require = createRequire(import.meta.url);
const OSS = require("ali-oss");

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, "..");
const localPath = join(root, "install-plugin.sh");

const region = process.env.OSS_REGION ?? "";
const accessKeyId = process.env.OSS_ACCESS_KEY_ID ?? "";
const accessKeySecret = process.env.OSS_ACCESS_KEY_SECRET ?? "";
const bucket = process.env.OSS_BUCKET ?? "";

if (!region || !accessKeyId || !accessKeySecret || !bucket) {
  console.error(
    "缺少环境变量：请设置 OSS_REGION、OSS_ACCESS_KEY_ID、OSS_ACCESS_KEY_SECRET、OSS_BUCKET 后重试。"
  );
  process.exit(1);
}

const objectKey = "scripts/install-plugin.sh";
const body = readFileSync(localPath);

const client = new OSS({
  region,
  accessKeyId,
  accessKeySecret,
  bucket,
});

const result = await client.put(objectKey, body, {
  headers: {
    "Content-Type": "text/x-shellscript; charset=utf-8",
  },
});

console.log("上传成功:", result.url ?? objectKey);
