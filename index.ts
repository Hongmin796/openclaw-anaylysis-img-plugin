import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { analyzeImage } from "./src/analyze-image.js";
import { uploadLocalFile, uploadFromUrl, type OssConfig } from "./src/oss-upload.js";

/** 与 openclaw.plugin.json 中 configSchema 对齐；字段均可选，由 env 兜底 */
type PluginConfig = {
  apiKey?: string;
  model?: string;
  oss?: Partial<OssConfig>;
};

function resolveConfig(api: { pluginConfig?: unknown }): {
  apiKey: string;
  model: string;
  ossCfg: OssConfig;
} {
  const cfg = (api.pluginConfig ?? {}) as PluginConfig;
  return {
    // 插件配置优先于进程环境变量（便于在 openclaw.json 中管理）
    apiKey: cfg.apiKey ?? process.env.DOUBAO_API_KEY ?? "",
    model: cfg.model ?? process.env.DOUBAO_MODEL ?? "doubao-seed-2-0-pro-260215",
    ossCfg: {
      region: cfg.oss?.region ?? process.env.OSS_REGION ?? "",
      accessKeyId: cfg.oss?.accessKeyId ?? process.env.OSS_ACCESS_KEY_ID ?? "",
      accessKeySecret: cfg.oss?.accessKeySecret ?? process.env.OSS_ACCESS_KEY_SECRET ?? "",
      bucket: cfg.oss?.bucket ?? process.env.OSS_BUCKET ?? "",
    },
  };
}

export default definePluginEntry({
  id: "openclaw-image-analysis",
  name: "Image Analysis Plugin",
  description: "Analyzes images using Doubao multimodal model, and uploads files to Aliyun OSS",
  register(api) {
    const { apiKey, model, ossCfg } = resolveConfig(api);

    // ── 工具1：图片分析 ──────────────────────────────────────────────
    api.registerTool({
      name: "analyze_image",
      label: "analyze_image",
      description: "Analyze an image using the Doubao multimodal model. Provide an image URL and a description of what to analyze.",
      parameters: Type.Object({
        image_url: Type.String({ description: "The URL of the image to analyze" }),
        desc: Type.String({ description: "Description of how to analyze the image" }),
      }),
      async execute(_id, params) {
        if (!apiKey || !model) {
          return {
            content: [{ type: "text", text: "Plugin not configured: set apiKey and model in plugin config, or DOUBAO_API_KEY / DOUBAO_MODEL environment variables." }],
            details: undefined,
          };
        }

        const result = await analyzeImage({
          apiKey,
          model,
          imageUrl: params.image_url,
          desc: params.desc,
        });

        return {
          content: [{ type: "text", text: result.ok ? result.content : result.error }],
          details: undefined,
        };
      },
    });

    // ── 工具2：上传本地文件到 OSS ────────────────────────────────────
    api.registerTool({
      name: "upload_local_file_to_oss",
      label: "upload_local_file_to_oss",
      description: "Upload a local file to Aliyun OSS bucket using stream upload.",
      parameters: Type.Object({
        local_path: Type.String({ description: "Absolute path of the local file to upload" }),
        object_path: Type.String({ description: "Target object path in OSS, e.g. exampledir/exampleobject.txt" }),
      }),
      async execute(_id, params) {
        if (!ossCfg.region || !ossCfg.accessKeyId || !ossCfg.accessKeySecret || !ossCfg.bucket) {
          return {
            content: [{ type: "text", text: "Plugin not configured: set oss.* in plugin config, or OSS_REGION, OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET environment variables." }],
            details: undefined,
          };
        }

        const result = await uploadLocalFile(ossCfg, params.local_path, params.object_path);
        const text = result.ok
          ? `上传成功\nObject: ${result.name}\nURL: ${result.url}`
          : `上传失败: ${result.error}`;

        return {
          content: [{ type: "text", text }],
          details: undefined,
        };
      },
    });

    // ── 工具3：将 URL 文件转存到 OSS ────────────────────────────────
    api.registerTool({
      name: "upload_url_to_oss",
      label: "upload_url_to_oss",
      description: "Download a file from a remote URL and upload it to Aliyun OSS bucket using stream upload.",
      parameters: Type.Object({
        source_url: Type.String({ description: "The URL of the remote file to upload" }),
        object_path: Type.String({ description: "Target object path in OSS, e.g. images/photo.jpg" }),
      }),
      async execute(_id, params) {
        if (!ossCfg.region || !ossCfg.accessKeyId || !ossCfg.accessKeySecret || !ossCfg.bucket) {
          return {
            content: [{ type: "text", text: "Plugin not configured: set oss.* in plugin config, or OSS_REGION, OSS_ACCESS_KEY_ID, OSS_ACCESS_KEY_SECRET, OSS_BUCKET environment variables." }],
            details: undefined,
          };
        }

        const result = await uploadFromUrl(ossCfg, params.source_url, params.object_path);
        const text = result.ok
          ? `上传成功\nObject: ${result.name}\nURL: ${result.url}`
          : `上传失败: ${result.error}`;

        return {
          content: [{ type: "text", text }],
          details: undefined,
        };
      },
    });
  },
});
