import { definePluginEntry } from "openclaw/plugin-sdk/plugin-entry";
import { Type } from "@sinclair/typebox";
import { analyzeImage } from "./src/analyze-image.js";
import { uploadLocalFile, uploadFromUrl, type OssConfig } from "./src/oss-upload.js";

type PluginConfig = {
  apiKey: string;
  model: string;
  oss: OssConfig;
};

export default definePluginEntry({
  id: "image-analysis-plugin",
  name: "Image Analysis Plugin",
  description: "Analyzes images using Doubao multimodal model, and uploads files to Aliyun OSS",
  register(api) {
    const cfg = (api.pluginConfig ?? {}) as PluginConfig;

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
        if (!cfg.apiKey || !cfg.model) {
          return {
            content: [{ type: "text", text: "Plugin not configured: apiKey and model are required." }],
            details: undefined,
          };
        }

        const result = await analyzeImage({
          apiKey: cfg.apiKey,
          model: cfg.model,
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
        if (!cfg.oss?.region || !cfg.oss?.accessKeyId || !cfg.oss?.accessKeySecret || !cfg.oss?.bucket) {
          return {
            content: [{ type: "text", text: "Plugin not configured: oss.region, oss.accessKeyId, oss.accessKeySecret, oss.bucket are required." }],
            details: undefined,
          };
        }

        const result = await uploadLocalFile(cfg.oss, params.local_path, params.object_path);
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
        if (!cfg.oss?.region || !cfg.oss?.accessKeyId || !cfg.oss?.accessKeySecret || !cfg.oss?.bucket) {
          return {
            content: [{ type: "text", text: "Plugin not configured: oss.region, oss.accessKeyId, oss.accessKeySecret, oss.bucket are required." }],
            details: undefined,
          };
        }

        const result = await uploadFromUrl(cfg.oss, params.source_url, params.object_path);
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
