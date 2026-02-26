import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Bindings } from "./types";
import { authMiddleware } from "./middleware/auth";
import { tasks } from "./routes/tasks";
import { createMcpServer } from "./mcp/server";
import { authHandler, validateAccessToken } from "./mcp/auth";
import { WebStandardStreamableHTTPServerTransport } from "@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js";

// ── Hono REST API（既存） ──
const app = new Hono<{ Bindings: Bindings }>();
app.use("/api/*", cors());
app.use("/api/*", authMiddleware);
app.route("/api", tasks);
app.get("/", (c) => c.json({ status: "ok", service: "taskm-api" }));

// ── Export ──
export default {
  async fetch(request: Request, env: Bindings, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;

    // OAuth endpoints
    if (
      path === "/authorize" ||
      path === "/token" ||
      path === "/register" ||
      path === "/.well-known/oauth-authorization-server" ||
      path === "/.well-known/oauth-protected-resource"
    ) {
      return authHandler.fetch(request, env);
    }

    // MCP endpoint
    if (path === "/mcp" || path.startsWith("/mcp/")) {
      return handleMcp(request, env);
    }

    // Existing Hono REST API
    return app.fetch(request, env, ctx);
  },
};

async function handleMcp(request: Request, env: Bindings): Promise<Response> {
  // CORS preflight
  if (request.method === "OPTIONS") {
    return new Response(null, {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Authorization, mcp-session-id",
      },
    });
  }

  // Bearer token認証
  const authHeader = request.headers.get("Authorization");
  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return Response.json(
      { error: "unauthorized", error_description: "Bearer token required" },
      {
        status: 401,
        headers: {
          "WWW-Authenticate": `Bearer resource_metadata="${new URL(request.url).origin}/.well-known/oauth-protected-resource"`,
        },
      }
    );
  }

  const token = authHeader.slice(7);
  const email = await validateAccessToken(token, env);
  if (!email) {
    return Response.json(
      { error: "invalid_token", error_description: "Token expired or invalid" },
      {
        status: 401,
        headers: {
          "WWW-Authenticate": `Bearer error="invalid_token", resource_metadata="${new URL(request.url).origin}/.well-known/oauth-protected-resource"`,
        },
      }
    );
  }

  // MCP Streamable HTTP transport (Web Standard - Workers compatible)
  const server = createMcpServer(env);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined,  // Stateless mode for Workers
    enableJsonResponse: true,
  });

  await server.connect(transport);

  const response = await transport.handleRequest(request);
  return response;
}
