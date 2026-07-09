export const config = {
  runtime: "edge",
};

type ChatChoice = {
  message?: {
    content?: string;
  };
};

type ChatResponse = {
  choices?: ChatChoice[];
};

const DEFAULT_BASE_URL = "https://api.openai.com/v1";
const DEFAULT_MODEL = "gpt-4.1-mini";

export default async function handler(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const expectedAppToken = process.env.AI_PROXY_APP_TOKEN;
  if (expectedAppToken) {
    const appToken = req.headers.get("x-todo-capsule-token") ?? "";
    if (appToken !== expectedAppToken) {
      return json({ error: "Unauthorized" }, 401);
    }
  }

  const apiKey = process.env.AI_PROXY_API_KEY;
  if (!apiKey) {
    return json({ error: "Proxy is not configured" }, 500);
  }

  let body: unknown;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const prompt = typeof body === "object" && body !== null && "prompt" in body
    ? String((body as { prompt?: unknown }).prompt ?? "").trim()
    : "";
  const maxPromptChars = Number(process.env.AI_PROXY_MAX_PROMPT_CHARS ?? "12000");

  if (!prompt) {
    return json({ error: "Missing prompt" }, 400);
  }
  if (prompt.length > maxPromptChars) {
    return json({ error: "Prompt is too long" }, 413);
  }

  const chatURL = chatCompletionsURL(process.env.AI_PROXY_BASE_URL ?? DEFAULT_BASE_URL);
  const model = process.env.AI_PROXY_MODEL ?? DEFAULT_MODEL;

  try {
    const upstream = await fetch(chatURL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model,
        messages: [
          {
            role: "system",
            content: "你是一个简洁、诚实、善于归纳行动项的待办总结助手。",
          },
          { role: "user", content: prompt },
        ],
        temperature: 0.3,
      }),
    });

    if (!upstream.ok) {
      return json({ error: "Model request failed" }, upstream.status);
    }

    const data = (await upstream.json()) as ChatResponse;
    const text = data.choices?.[0]?.message?.content?.trim() ?? "";
    if (!text) {
      return json({ error: "Empty model response" }, 502);
    }

    return json({ text });
  } catch {
    return json({ error: "Proxy request failed" }, 502);
  }
}

function chatCompletionsURL(baseURL: string): string {
  const trimmed = baseURL.endsWith("/") ? baseURL.slice(0, -1) : baseURL;
  if (trimmed.endsWith("/chat/completions")) {
    return trimmed;
  }
  if (trimmed.endsWith("/v1")) {
    return `${trimmed}/chat/completions`;
  }
  return `${trimmed}/v1/chat/completions`;
}

function json(body: Record<string, unknown>, status = 200): Response {
  return Response.json(body, {
    status,
    headers: {
      "Cache-Control": "no-store",
    },
  });
}
