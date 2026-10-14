// JSON in and out, and the one error type routes throw.
//
// Errors are `{"error": "<a sentence for people>", "code": "<machine code>"}` (docs/milestones/M2.md):
// the app switches on `code`, never on `error`.

/** Machine codes for errors that aren't specific to a route. */
const DEFAULT_CODES: Readonly<Record<number, string>> = {
  400: "bad_request",
  401: "unauthorised",
  404: "not_found",
  413: "too_large",
  500: "internal",
  502: "upstream_unavailable",
};

/** Thrown by a route; `handle` turns it into `{"error": message, "code": code}` with this status. */
export class HttpError extends Error {
  override name = "HttpError";
  readonly status: number;
  readonly code: string;

  constructor(status: number, message: string, code?: string) {
    super(message);
    this.status = status;
    this.code = code ?? DEFAULT_CODES[status] ?? (status >= 500 ? "internal" : "bad_request");
  }
}

/** An error from the contract: `apiError(409, "handle_taken", "That handle is taken")`. */
export function apiError(status: number, code: string, message: string): HttpError {
  return new HttpError(status, message, code);
}

export function json(body: unknown, status = 200, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

export function errorResponse(error: HttpError): Response {
  return json({ error: error.message, code: error.code }, error.status);
}

export function noContent(): Response {
  return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
}

export function notFound(): Response {
  return json({ error: "Not found", code: "not_found" }, 404);
}

/** A whole HTML page with no external assets: inline styles only, nothing else may load. */
export function html(body: string, status = 200): Response {
  return new Response(body, {
    status,
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
      "referrer-policy": "no-referrer",
      "x-content-type-options": "nosniff",
      "x-robots-tag": "noindex",
    },
  });
}

/** Text made safe for HTML element content and quoted attribute values. */
export function escapeHTML(text: string): string {
  return text.replace(/[&<>"'`]/g, (character) => `&#${character.charCodeAt(0)};`);
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

/** `readJSON`, refusing anything but a JSON object. */
export async function readObject(request: Request): Promise<Record<string, unknown>> {
  const body = await readJSON(request);
  if (!isRecord(body)) throw new HttpError(400, "Expected a JSON object");
  return body;
}

export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The token from `Authorization: Bearer <token>`, or "" without one. */
export function bearerToken(request: Request): string {
  const match = /^Bearer[ \t]+(\S+)[ \t]*$/i.exec(request.headers.get("authorization") ?? "");
  return match?.[1] ?? "";
}

/**
 * Whether the request carries `Authorization: Bearer <expected>`, compared in constant time.
 *
 * Both sides are hashed first, so they're the same length and the comparison's timing says nothing
 * about how much of the token was right. (Workers have `crypto.subtle.timingSafeEqual`, but Node,
 * where the tests run, doesn't.)
 */
export async function hasBearerToken(request: Request, expected: string): Promise<boolean> {
  const presented = bearerToken(request);
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
