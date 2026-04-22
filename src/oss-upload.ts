import { createRequire } from "node:module";
import fs from "node:fs";
import { Readable } from "node:stream";

const require = createRequire(import.meta.url);
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const OSS = require("ali-oss") as any;

export type OssConfig = {
  region: string;
  accessKeyId: string;
  accessKeySecret: string;
  bucket: string;
};

export type OssUploadResult =
  | { ok: true; url: string; name: string }
  | { ok: false; error: string };

function createClient(cfg: OssConfig) {
  return new OSS({
    region: cfg.region,
    accessKeyId: cfg.accessKeyId,
    accessKeySecret: cfg.accessKeySecret,
    bucket: cfg.bucket,
  });
}

export async function uploadLocalFile(
  ossCfg: OssConfig,
  localPath: string,
  objectPath: string
): Promise<OssUploadResult> {
  if (!fs.existsSync(localPath)) {
    return { ok: false, error: `本地文件不存在: ${localPath}` };
  }

  try {
    const client = createClient(ossCfg);
    const stream = fs.createReadStream(localPath);
    const result = await client.putStream(objectPath, stream);
    return { ok: true, url: result.url, name: result.name };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
}

export async function uploadFromUrl(
  ossCfg: OssConfig,
  sourceUrl: string,
  objectPath: string
): Promise<OssUploadResult> {
  let response: Response;
  try {
    response = await fetch(sourceUrl);
  } catch (err) {
    return { ok: false, error: `请求源 URL 失败: ${String(err)}` };
  }

  if (!response.ok) {
    return { ok: false, error: `源 URL 返回错误 ${response.status}: ${sourceUrl}` };
  }

  if (!response.body) {
    return { ok: false, error: "源 URL 响应没有 body" };
  }

  try {
    const client = createClient(ossCfg);
    // 将 Web ReadableStream 转换为 Node.js Readable 再传给 putStream
    const nodeStream = Readable.fromWeb(response.body as Parameters<typeof Readable.fromWeb>[0]);
    const result = await client.putStream(objectPath, nodeStream);
    return { ok: true, url: result.url, name: result.name };
  } catch (err) {
    return { ok: false, error: String(err) };
  }
}
