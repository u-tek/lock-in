// A live squad session ("room"): one Durable Object per session id (SPEC.md §4). M3 fills it in:
// room state, the content-state, coalescing, the APNs fan-out and the WebSocket live view.
//
// A plain class rather than `extends DurableObject` from "cloudflare:workers", so the tests can
// load it in Node. The runtime accepts a plain class with a `fetch` handler; extending
// DurableObject would only add RPC.

import type { Env } from "./env.ts";
import { json } from "./http.ts";

export class Room {
  private readonly state: DurableObjectState;
  /** M3: APNs credentials and D1. */
  readonly env: Env;

  constructor(state: DurableObjectState, env: Env) {
    this.state = state;
    this.env = env;
  }

  async fetch(request: Request): Promise<Response> {
    if (request.method === "GET") {
      // The snapshot shape GET /sessions/:id will return; nobody's in the room until M3.
      const sid = this.state.id.name ?? new URL(request.url).pathname.split("/").pop() ?? "";
      return json({ sid, members: [] });
    }
    // M3: join, pause, resume, end, slip, cheer, la-token and the live WebSocket.
    return json({ error: "Rooms arrive in M3" }, 501);
  }
}
