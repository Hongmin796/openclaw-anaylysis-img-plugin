const API_URL = "https://ark.cn-beijing.volces.com/api/v3/chat/completions";

export type AnalyzeImageParams = {
  apiKey: string;
  model: string;
  imageUrl: string;
  desc: string;
};

export type AnalyzeImageResult =
  | { ok: true; content: string }
  | { ok: false; error: string };

export async function analyzeImage(params: AnalyzeImageParams): Promise<AnalyzeImageResult> {
  const { apiKey, model, imageUrl, desc } = params;

  let response: Response;
  try {
    response = await fetch(API_URL, {
      method: "POST",
      headers: {
        "Accept": "*/*",
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "user",
            content: [
              { type: "image_url", image_url: { url: imageUrl } },
              { type: "text", text: desc },
            ],
          },
        ],
      }),
    });
  } catch (err) {
    return { ok: false, error: `Network error: ${String(err)}` };
  }

  if (!response.ok) {
    const errorText = await response.text();
    return { ok: false, error: `API error ${response.status}: ${errorText}` };
  }

  const data = await response.json() as {
    choices: Array<{ message: { content: string } }>;
  };

  const content = data.choices?.[0]?.message?.content ?? "No response from model";
  return { ok: true, content };
}
