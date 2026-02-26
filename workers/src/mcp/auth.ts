import type { Bindings } from "../types";

/**
 * OAuth認可ハンドラ
 * /authorize にリダイレクトされたとき、メールアドレスで認証する簡易フォームを表示。
 * 許可されたメールアドレスのみ認可コードを発行する。
 */
export const authHandler = {
  fetch: async (request: Request, env: Bindings): Promise<Response> => {
    const url = new URL(request.url);

    // 認可画面（GET /authorize）
    if (url.pathname === "/authorize" && request.method === "GET") {
      // OAuthパラメータを保持
      const params = url.searchParams;
      return new Response(renderAuthPage(params), {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    // 認可処理（POST /authorize）
    if (url.pathname === "/authorize" && request.method === "POST") {
      const formData = await request.formData();
      const email = (formData.get("email") as string || "").trim().toLowerCase();

      // OAuthパラメータを復元
      const clientId = formData.get("client_id") as string;
      const redirectUri = formData.get("redirect_uri") as string;
      const state = formData.get("state") as string;
      const codeChallenge = formData.get("code_challenge") as string;
      const codeChallengeMethod = formData.get("code_challenge_method") as string;
      const scope = formData.get("scope") as string;

      // メールアドレス検証
      const allowedEmail = (env.ALLOWED_EMAIL || "").toLowerCase();
      if (!email || email !== allowedEmail) {
        return new Response(renderAuthPage(new URLSearchParams({
          client_id: clientId || "",
          redirect_uri: redirectUri || "",
          state: state || "",
          code_challenge: codeChallenge || "",
          code_challenge_method: codeChallengeMethod || "",
          scope: scope || "",
        }), "このメールアドレスは許可されていません。"), {
          status: 403,
          headers: { "Content-Type": "text/html; charset=utf-8" },
        });
      }

      // 認可コード生成
      const code = crypto.randomUUID();

      // 認可コードをKVに保存（5分間有効）
      await env.OAUTH_KV.put(`auth_code:${code}`, JSON.stringify({
        email,
        clientId,
        redirectUri,
        codeChallenge,
        codeChallengeMethod,
        scope,
      }), { expirationTtl: 300 });

      // リダイレクトURIに認可コードを付与
      const redirect = new URL(redirectUri);
      redirect.searchParams.set("code", code);
      if (state) redirect.searchParams.set("state", state);

      return Response.redirect(redirect.toString(), 302);
    }

    // トークンエンドポイント（POST /token）
    if (url.pathname === "/token" && request.method === "POST") {
      return handleTokenRequest(request, env);
    }

    // Dynamic Client Registration（RFC 7591）
    if (url.pathname === "/register" && request.method === "POST") {
      const body = await request.json<{
        client_name?: string;
        redirect_uris?: string[];
        grant_types?: string[];
        response_types?: string[];
        token_endpoint_auth_method?: string;
      }>();

      const clientId = crypto.randomUUID();
      // KVにクライアント情報を保存（無期限）
      await env.OAUTH_KV.put(`client:${clientId}`, JSON.stringify({
        client_id: clientId,
        client_name: body.client_name || "Unknown",
        redirect_uris: body.redirect_uris || [],
        grant_types: body.grant_types || ["authorization_code"],
        response_types: body.response_types || ["code"],
        token_endpoint_auth_method: body.token_endpoint_auth_method || "none",
      }));

      return Response.json({
        client_id: clientId,
        client_name: body.client_name || "Unknown",
        redirect_uris: body.redirect_uris || [],
        grant_types: body.grant_types || ["authorization_code"],
        response_types: body.response_types || ["code"],
        token_endpoint_auth_method: body.token_endpoint_auth_method || "none",
      }, { status: 201 });
    }

    // OAuth metadata（RFC 8414）
    if (url.pathname === "/.well-known/oauth-authorization-server") {
      const origin = url.origin;
      return Response.json({
        issuer: origin,
        authorization_endpoint: `${origin}/authorize`,
        token_endpoint: `${origin}/token`,
        registration_endpoint: `${origin}/register`,
        response_types_supported: ["code"],
        grant_types_supported: ["authorization_code", "refresh_token"],
        code_challenge_methods_supported: ["S256", "plain"],
        token_endpoint_auth_methods_supported: ["none"],
      });
    }

    // MCP Protected Resource Metadata (RFC 9728)
    if (url.pathname === "/.well-known/oauth-protected-resource") {
      const origin = url.origin;
      return Response.json({
        resource: origin,
        authorization_servers: [origin],
      });
    }

    return new Response("Not Found", { status: 404 });
  },
};

async function handleTokenRequest(request: Request, env: Bindings): Promise<Response> {
  const body = await request.formData();
  const grantType = body.get("grant_type") as string;

  if (grantType === "authorization_code") {
    const code = body.get("code") as string;
    const codeVerifier = body.get("code_verifier") as string;

    // 認可コードを検証
    const stored = await env.OAUTH_KV.get(`auth_code:${code}`);
    if (!stored) {
      return Response.json({ error: "invalid_grant", error_description: "Invalid or expired authorization code" }, { status: 400 });
    }

    const authData = JSON.parse(stored);
    await env.OAUTH_KV.delete(`auth_code:${code}`);

    // PKCE検証
    if (authData.codeChallenge && codeVerifier) {
      const valid = await verifyPKCE(codeVerifier, authData.codeChallenge, authData.codeChallengeMethod || "S256");
      if (!valid) {
        return Response.json({ error: "invalid_grant", error_description: "PKCE verification failed" }, { status: 400 });
      }
    }

    // トークン生成
    const accessToken = crypto.randomUUID();
    const refreshToken = crypto.randomUUID();

    // アクセストークン（1時間）
    await env.OAUTH_KV.put(`access_token:${accessToken}`, JSON.stringify({
      email: authData.email,
      scope: authData.scope,
    }), { expirationTtl: 3600 });

    // リフレッシュトークン（90日）
    await env.OAUTH_KV.put(`refresh_token:${refreshToken}`, JSON.stringify({
      email: authData.email,
      scope: authData.scope,
    }), { expirationTtl: 90 * 24 * 3600 });

    return Response.json({
      access_token: accessToken,
      token_type: "Bearer",
      expires_in: 3600,
      refresh_token: refreshToken,
      scope: authData.scope || "",
    });
  }

  if (grantType === "refresh_token") {
    const refreshToken = body.get("refresh_token") as string;

    const stored = await env.OAUTH_KV.get(`refresh_token:${refreshToken}`);
    if (!stored) {
      return Response.json({ error: "invalid_grant", error_description: "Invalid or expired refresh token" }, { status: 400 });
    }

    const tokenData = JSON.parse(stored);

    // 新しいアクセストークン発行
    const newAccessToken = crypto.randomUUID();
    await env.OAUTH_KV.put(`access_token:${newAccessToken}`, JSON.stringify({
      email: tokenData.email,
      scope: tokenData.scope,
    }), { expirationTtl: 3600 });

    // 新しいリフレッシュトークン（ローテーション）
    const newRefreshToken = crypto.randomUUID();
    await env.OAUTH_KV.put(`refresh_token:${newRefreshToken}`, JSON.stringify({
      email: tokenData.email,
      scope: tokenData.scope,
    }), { expirationTtl: 90 * 24 * 3600 });

    // 古いリフレッシュトークンを無効化
    await env.OAUTH_KV.delete(`refresh_token:${refreshToken}`);

    return Response.json({
      access_token: newAccessToken,
      token_type: "Bearer",
      expires_in: 3600,
      refresh_token: newRefreshToken,
      scope: tokenData.scope || "",
    });
  }

  return Response.json({ error: "unsupported_grant_type" }, { status: 400 });
}

async function verifyPKCE(verifier: string, challenge: string, method: string): Promise<boolean> {
  if (method === "plain") {
    return verifier === challenge;
  }
  // S256
  const encoder = new TextEncoder();
  const data = encoder.encode(verifier);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const base64 = btoa(String.fromCharCode(...new Uint8Array(hash)))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
  return base64 === challenge;
}

export async function validateAccessToken(token: string, env: Bindings): Promise<string | null> {
  const stored = await env.OAUTH_KV.get(`access_token:${token}`);
  if (!stored) return null;
  const data = JSON.parse(stored);
  return data.email;
}

function renderAuthPage(params: URLSearchParams, errorMsg?: string): string {
  return `<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>TaskM - 認証</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #1a1a2e; color: #e0e0e0; display: flex; justify-content: center; align-items: center; min-height: 100vh; margin: 0; }
    .card { background: #16213e; border-radius: 12px; padding: 2rem; max-width: 400px; width: 90%; box-shadow: 0 4px 20px rgba(0,0,0,0.3); }
    h1 { text-align: center; color: #7bc8a4; margin-bottom: 0.5rem; }
    p { text-align: center; color: #9b9b9b; font-size: 0.9rem; }
    .error { color: #e74c3c; text-align: center; margin: 1rem 0; }
    input[type="email"] { width: 100%; padding: 0.8rem; border: 1px solid #333; border-radius: 8px; background: #0f3460; color: #e0e0e0; font-size: 1rem; margin: 1rem 0; box-sizing: border-box; }
    button { width: 100%; padding: 0.8rem; background: #7bc8a4; color: #1a1a2e; border: none; border-radius: 8px; font-size: 1rem; font-weight: 600; cursor: pointer; }
    button:hover { background: #5fb88a; }
  </style>
</head>
<body>
  <div class="card">
    <h1>TaskM</h1>
    <p>タスク管理へのアクセスを認証します</p>
    ${errorMsg ? `<div class="error">${errorMsg}</div>` : ""}
    <form method="POST" action="/authorize">
      <input type="email" name="email" placeholder="メールアドレス" required autofocus>
      <input type="hidden" name="client_id" value="${escapeHtml(params.get("client_id") || "")}">
      <input type="hidden" name="redirect_uri" value="${escapeHtml(params.get("redirect_uri") || "")}">
      <input type="hidden" name="state" value="${escapeHtml(params.get("state") || "")}">
      <input type="hidden" name="code_challenge" value="${escapeHtml(params.get("code_challenge") || "")}">
      <input type="hidden" name="code_challenge_method" value="${escapeHtml(params.get("code_challenge_method") || "")}">
      <input type="hidden" name="scope" value="${escapeHtml(params.get("scope") || "")}">
      <button type="submit">認証する</button>
    </form>
  </div>
</body>
</html>`;
}

function escapeHtml(str: string): string {
  return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}
