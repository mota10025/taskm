import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Bindings } from "./types";
import { authMiddleware } from "./middleware/auth";
import { tasks } from "./routes/tasks";

const app = new Hono<{ Bindings: Bindings }>();

app.use("/api/*", cors());
app.use("/api/*", authMiddleware);

app.route("/api", tasks);

app.get("/", (c) => c.json({ status: "ok", service: "taskm-api" }));

export default app;
