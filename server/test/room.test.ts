import { expect, test } from "vitest";
import type { Env } from "../src/env.ts";
import { Room } from "../src/room.ts";

function room(name?: string): Room {
  const state = { id: { name, toString: () => "0123abcd", equals: () => false } } as unknown as DurableObjectState;
  return new Room(state, {} as Env);
}

test("GET answers with an empty snapshot until M3", async () => {
  const response = await room("r7Kq2xP9aL").fetch(new Request("https://room/sessions/r7Kq2xP9aL"));
  expect(response.status).toBe(200);
  expect(await response.json()).toEqual({ sid: "r7Kq2xP9aL", members: [] });

  const unnamed = await room().fetch(new Request("https://room/sessions/Ka9Lm3Vx0c"));
  expect(await unnamed.json()).toEqual({ sid: "Ka9Lm3Vx0c", members: [] });
});

test("everything else is 501 until M3", async () => {
  const response = await room("r7Kq2xP9aL").fetch(new Request("https://room/sessions/r7Kq2xP9aL/join", { method: "POST" }));
  expect(response.status).toBe(501);
});
