import type { MiddlewareHandler } from "hono";
import type { Bindings } from "../types";

export const authMiddleware: MiddlewareHandler<{ Bindings: Bindings }> = async (
  c,
  next
) => {
  const apiKey = c.req.header("X-API-Key");
  if (apiKey !== c.env.API_KEY) {
    return c.json({ success: false, error: "Unauthorized" }, 401);
  }
  await next();
};
