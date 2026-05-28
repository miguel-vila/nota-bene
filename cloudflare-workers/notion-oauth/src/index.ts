interface Env {
  NOTION_CLIENT_ID: string;
  NOTION_CLIENT_SECRET: string;
  APP_REDIRECT_SCHEME: string;
}

interface ExchangeRequest {
  code: unknown;
  redirect_uri: unknown;
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    try {
      if (req.method === "GET" && url.pathname === "/oauth/notion/callback") {
        return handleCallback(url, env);
      }
      if (req.method === "POST" && url.pathname === "/oauth/notion/exchange") {
        return await handleExchange(req, env);
      }
      return json({ error: "not_found" }, 404);
    } catch (err) {
      console.error(
        JSON.stringify({
          level: "error",
          msg: "unhandled_error",
          path: url.pathname,
          error: err instanceof Error ? err.message : String(err),
        }),
      );
      return json({ error: "internal_error" }, 500);
    }
  },
};

function handleCallback(url: URL, env: Env): Response {
  const target = new URL(env.APP_REDIRECT_SCHEME);
  for (const [k, v] of url.searchParams) {
    target.searchParams.set(k, v);
  }
  console.log(
    JSON.stringify({
      level: "info",
      msg: "callback_forward",
      has_code: url.searchParams.has("code"),
      has_error: url.searchParams.has("error"),
    }),
  );
  return new Response(null, {
    status: 302,
    headers: { Location: target.toString() },
  });
}

async function handleExchange(req: Request, env: Env): Promise<Response> {
  let body: ExchangeRequest;
  try {
    body = (await req.json()) as ExchangeRequest;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const code = typeof body.code === "string" ? body.code : "";
  const redirectURI = typeof body.redirect_uri === "string" ? body.redirect_uri : "";
  if (!code || !redirectURI) {
    return json({ error: "invalid_request" }, 400);
  }

  const basic = btoa(`${env.NOTION_CLIENT_ID}:${env.NOTION_CLIENT_SECRET}`);
  const notionResp = await fetch("https://api.notion.com/v1/oauth/token", {
    method: "POST",
    headers: {
      Authorization: `Basic ${basic}`,
      "Content-Type": "application/json",
      Accept: "application/json",
    },
    body: JSON.stringify({
      grant_type: "authorization_code",
      code,
      redirect_uri: redirectURI,
    }),
  });

  const text = await notionResp.text();
  console.log(
    JSON.stringify({
      level: notionResp.ok ? "info" : "warn",
      msg: "exchange_complete",
      status: notionResp.status,
    }),
  );
  return new Response(text, {
    status: notionResp.status,
    headers: { "Content-Type": "application/json" },
  });
}

function json(payload: unknown, status: number): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
