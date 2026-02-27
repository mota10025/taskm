import { Hono } from "hono";
import { z } from "zod";
import type { Bindings, Category } from "../types";
import { nowJST } from "../utils/date";

const colorHex = z.string().regex(/^#[0-9a-fA-F]{6}$/);

const createSchema = z.object({
  name: z.string().min(1, "name は必須です。"),
  color: colorHex,
  text_color: colorHex.optional(),
});

const updateSchema = z.object({
  name: z.string().min(1).optional(),
  color: colorHex.optional(),
  text_color: colorHex.optional(),
});

const categories = new Hono<{ Bindings: Bindings }>();

// POST /categories - カテゴリ追加
categories.post("/categories", async (c) => {
  const raw = await c.req.json().catch(() => null);
  if (!raw) {
    return c.json({ success: false, error: "無効なJSONです。" }, 400);
  }
  const parsed = createSchema.safeParse(raw);
  if (!parsed.success) {
    return c.json({ success: false, error: parsed.error.issues[0].message }, 400);
  }
  const { name, color, text_color } = parsed.data;
  const textColor = text_color ?? "#2a2a2a";
  const { datetime } = nowJST();

  const existing = await c.env.DB.prepare("SELECT name FROM categories WHERE name = ?")
    .bind(name)
    .first();
  if (existing) {
    return c.json({ success: false, error: `カテゴリ「${name}」は既に存在します。` }, 409);
  }

  await c.env.DB.prepare(
    "INSERT INTO categories (name, color, text_color, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
  )
    .bind(name, color, textColor, datetime, datetime)
    .run();

  return c.json({ success: true, message: `カテゴリ「${name}」を追加しました。` }, 201);
});

// PUT /categories/:name - カテゴリ更新
categories.put("/categories/:name", async (c) => {
  const oldName = decodeURIComponent(c.req.param("name"));
  const existing = await c.env.DB.prepare("SELECT * FROM categories WHERE name = ?")
    .bind(oldName)
    .first<Category>();
  if (!existing) {
    return c.json({ success: false, error: `カテゴリ「${oldName}」は見つかりません。` }, 404);
  }

  const raw = await c.req.json().catch(() => null);
  if (!raw) {
    return c.json({ success: false, error: "無効なJSONです。" }, 400);
  }
  const parsed = updateSchema.safeParse(raw);
  if (!parsed.success) {
    return c.json({ success: false, error: parsed.error.issues[0].message }, 400);
  }
  const body = parsed.data;
  const { datetime } = nowJST();

  const newName = body.name ?? oldName;
  const newColor = body.color ?? existing.color;
  const newTextColor = body.text_color ?? existing.text_color;

  const stmts: D1PreparedStatement[] = [];

  if (body.name && body.name !== oldName) {
    // 名前変更: 新レコード作成 → タスク更新 → 旧レコード削除
    stmts.push(
      c.env.DB.prepare(
        "INSERT INTO categories (name, color, text_color, created_at, updated_at) VALUES (?, ?, ?, ?, ?)"
      ).bind(newName, newColor, newTextColor, existing.created_at, datetime)
    );
    stmts.push(
      c.env.DB.prepare("UPDATE tasks SET category = ? WHERE category = ?").bind(newName, oldName)
    );
    stmts.push(c.env.DB.prepare("DELETE FROM categories WHERE name = ?").bind(oldName));
  } else {
    // 色・文字色変更
    stmts.push(
      c.env.DB.prepare("UPDATE categories SET color = ?, text_color = ?, updated_at = ? WHERE name = ?").bind(
        newColor,
        newTextColor,
        datetime,
        oldName
      )
    );
  }

  await c.env.DB.batch(stmts);

  return c.json({ success: true, message: `カテゴリ「${newName}」を更新しました。` });
});

// DELETE /categories/:name - カテゴリ削除
categories.delete("/categories/:name", async (c) => {
  const name = decodeURIComponent(c.req.param("name"));
  const existing = await c.env.DB.prepare("SELECT name FROM categories WHERE name = ?")
    .bind(name)
    .first();
  if (!existing) {
    return c.json({ success: false, error: `カテゴリ「${name}」は見つかりません。` }, 404);
  }

  await c.env.DB.prepare("DELETE FROM categories WHERE name = ?").bind(name).run();

  return c.json({ success: true, message: `カテゴリ「${name}」を削除しました。` });
});

export { categories };
