// JSON in and out, and the one error type routes throw.

/** Thrown by a route; `handle` turns it into `{"error": message}` with this status. */
export class HttpError extends Error {
  override name = "HttpError";
  readonly status: number;

  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" },
  });
}

export function notFound(): Response {
  return json({ error: "Not found" }, 404);
}

/** The request body parsed as JSON. Small bodies only: nothing the API takes comes close. */
export async function readJSON(request: Request, maxBytes = 16 * 1024): Promise<unknown> {
  const declared = Number(request.headers.get("content-length") ?? "0");
  if (declared > maxBytes) throw new HttpError(413, `The body is over ${maxBytes} bytes`);
  const text = await request.text();
  if (new TextEncoder().encode(text).length > maxBytes) throw new HttpError(413, `The body is over ${maxBytes} bytes`);
  if (text.trim().length === 0) throw new HttpError(400, "Expected a JSON body");
  try {
    return JSON.parse(text);
  } catch {
    throw new HttpError(400, "The body isn't valid JSON");
  }
}

/**
 * Whether the request carries `Authorization: Bearer <expected>`, compared in constant time.
 *
 * Both sides are hashed first, so they're the same length and the comparison's timing says nothing
 * about how much of the token was right. (Workers have `crypto.subtle.timingSafeEqual`, but Node,
 * where the tests run, doesn't.)
 */
export async function hasBearerToken(request: Request, expected: string): Promise<boolean> {
  const match = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(request.headers.get("authorization") ?? "");
  const presented = match?.[1] ?? "";
  const encoder = new TextEncoder();
  const [left, right] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(presented)),
    crypto.subtle.digest("SHA-256", encoder.encode(expected)),
  ]);
  const a = new Uint8Array(left);
  const b = new Uint8Array(right);
  let difference = presented.length === 0 ? 1 : 0;
  for (let i = 0; i < a.length; i++) difference |= (a[i] ?? 0) ^ (b[i] ?? 0);
  return difference === 0;
}
