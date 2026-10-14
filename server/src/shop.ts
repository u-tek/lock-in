// The coin shop (docs/milestones/M5.md): Lockling cosmetics bought with coins earned focusing.
//
//   GET  /shop             -> { items: [ShopItem] }
//   POST /shop/buy         { itemId } -> { coins, owned: [itemId] }
//   GET  /me/cosmetics     -> { owned: [itemId] }
//
// The catalogue is fixtures/shop/catalogue.json, shared with the app: every option of each part of a
// Lockling (body, colour, eyes, hat) but the free default, option 0, which everyone owns and which
// isn't listed. Plus items (SPEC.md §2) cost nothing and aren't bought: they're yours while Plus is.
// An item's id is `<part>.<option>`, the option being the number in the avatar code: "hat.3" is
// "h3" in "b0.c0.e0.h3".
//
// `owned` is what you can wear beyond the defaults: what you bought or imported, and every Plus
// item while you have Plus.
//
// M7: part `pet` is the squad pet's accessories (`pet.1` scarf … `pet.6` star clip), all Plus. They
// aren't worn by your Lockling and aren't in `owned`: Squad Boost unlocks them for a whole squad
// (PATCH /squads/:id/pet, src/squads.ts).

import catalogue from "../../fixtures/shop/catalogue.json";
import type { AuthedContext, Context } from "./context.ts";
import { type UserRow, isCheckViolation, isUniqueViolation } from "./db.ts";
import { HttpError, apiError, json, readObject } from "./http.ts";
import { hasPlus } from "./squads.ts";

export type ShopPart = "body" | "colour" | "eyes" | "hat" | "pet";

export interface ShopItem {
  /** `<part>.<option>`, e.g. "hat.1". */
  id: string;
  part: ShopPart;
  /** The number in the avatar code. Never 0: defaults aren't sold. */
  option: number;
  /** Coins; 0 for Plus items. */
  price: number;
  plus: boolean;
}

export const SHOP_ITEMS: readonly ShopItem[] = (catalogue as { items: ShopItem[] }).items;
const ITEMS_BY_ID = new Map(SHOP_ITEMS.map((item) => [item.id, item]));

/** The avatar code's letter for each part (Model's AvatarCode: `b<body>.c<colour>.e<eyes>.h<hat>`). */
export const PART_LETTERS: Readonly<Record<string, ShopPart>> = { b: "body", c: "colour", e: "eyes", h: "hat" };

export function shopItem(id: string): ShopItem | undefined {
  return ITEMS_BY_ID.get(id);
}

/** Whether `option` is one of the pet's accessories (`pet.<option>` in the catalogue), M7. */
export function isPetAccessory(option: unknown): option is number {
  return typeof option === "number" && Number.isInteger(option) && shopItem(`pet.${option}`)?.part === "pet";
}

/** The item each part of an avatar code names, by part: "b2.c0.e1.h0" -> body.2, eyes.1 (defaults left out). */
export function avatarItemIds(code: string): Map<ShopPart, string> {
  const parts = new Map<ShopPart, string>();
  for (const piece of code.split(".")) {
    const part = PART_LETTERS[piece.charAt(0)];
    const option = Number(piece.slice(1));
    if (part === undefined || !Number.isInteger(option) || option === 0 || parts.has(part)) continue;
    parts.set(part, `${part}.${option}`);
  }
  return parts;
}

/**
 * What the user can wear beyond the defaults, in catalogue order: bought or imported, and Plus
 * items while Plus lasts. The pet's accessories aren't worn by a Lockling, so they're never here.
 */
export async function ownedItems(context: Context, user: Pick<UserRow, "id" | "plus_until">): Promise<string[]> {
  const bought = new Set(await context.db.cosmeticsOf(user.id));
  const plus = hasPlus(user, context.now);
  return SHOP_ITEMS.filter((item) => item.part !== "pet" && (item.plus ? plus : bought.has(item.id))).map((item) => item.id);
}

/**
 * PATCH /me's check on a new avatar code: every part it changes must be a default or an item you
 * own (Plus items with Plus). Parts you're already wearing stay yours, so an old code (from before
 * the shop, when every free part was free) is left alone. 403 `item_not_owned` otherwise, naming
 * the item.
 */
export async function checkAvatarOwnership(context: AuthedContext, code: string): Promise<void> {
  const wearing = avatarItemIds(context.user.avatar_code);
  const changes = [...avatarItemIds(code)].filter(([part, itemId]) => wearing.get(part) !== itemId).map(([, itemId]) => itemId);
  if (changes.length === 0) return;
  const owned = new Set(await ownedItems(context, context.user));
  const missing = changes.find((itemId) => !owned.has(itemId));
  if (missing !== undefined) {
    const item = shopItem(missing);
    const message = item?.plus === true ? "That's a Lockin Plus item" : "You don't own that item yet";
    throw apiError(403, "item_not_owned", message, { itemId: missing });
  }
}

// GET /shop

export async function getShop(): Promise<Response> {
  return json({ items: SHOP_ITEMS });
}

// POST /shop/buy

/** Buys an item with coins. Plus items aren't sold: 402 `plus_required` without Plus, 409 `already_owned` with it. */
export async function buyItem(context: AuthedContext): Promise<Response> {
  const { db, user, now } = context;
  const body = await readObject(context.request);
  if (typeof body.itemId !== "string") throw new HttpError(400, "itemId must be a string");
  const item = shopItem(body.itemId);
  if (item === undefined) throw apiError(404, "item_not_found", "There's no such item");
  const alreadyOwned = () => apiError(409, "already_owned", "You already have this");
  const notEnoughCoins = () => apiError(402, "not_enough_coins", "Not enough coins yet. Lock in to earn more.");

  if (item.plus) {
    if (hasPlus(user, now)) throw alreadyOwned();
    throw apiError(402, "plus_required", "That's a Lockin Plus item");
  }
  if ((await db.cosmeticsOf(user.id)).includes(item.id)) throw alreadyOwned();
  if (user.coins < item.price) throw notEnoughCoins();

  let coins: number;
  try {
    coins = await db.buyItem(user.id, item.id, item.price, now);
  } catch (error) {
    // Another purchase got there first.
    if (isUniqueViolation(error, "cosmetics.user_id")) throw alreadyOwned();
    if (isCheckViolation(error, "coins")) throw notEnoughCoins();
    throw error;
  }
  console.log("shop: bought an item");
  return json({ coins, owned: await ownedItems(context, user) });
}

// GET /me/cosmetics

export async function myCosmetics(context: AuthedContext): Promise<Response> {
  return json({ owned: await ownedItems(context, context.user) });
}
