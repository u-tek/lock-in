// A D1-compatible database over Node's built-in node:sqlite (the same SQLite engine D1 runs), with
// every migration in migrations/ applied and foreign keys on, as D1 has them. Route tests run their
// real SQL through it.
//
// It covers what src/ uses: prepare().bind().first()/all()/run()/raw(), batch() (one transaction,
// rolled back if any statement fails, as D1 does) and exec(). Bind values follow D1's rules:
// `undefined` is refused, booleans become 1/0. Errors read like D1's ("D1_ERROR: UNIQUE constraint
// failed: users.handle: SQLITE_CONSTRAINT"), so code that matches on them is tested as deployed.

import { readFileSync, readdirSync } from "node:fs";
import { DatabaseSync, type SQLInputValue, type StatementSync } from "node:sqlite";

const MIGRATIONS = new URL("../migrations/", import.meta.url);

/** The migration files in the order wrangler applies them. */
export function migrationFiles(): string[] {
  return readdirSync(MIGRATIONS)
    .filter((name) => name.endsWith(".sql"))
    .sort();
}

/** A fresh in-memory database with every migration applied. */
export function migratedSQLite(): DatabaseSync {
  const db = new DatabaseSync(":memory:");
  db.exec("PRAGMA foreign_keys = ON");
  for (const file of migrationFiles()) db.exec(readFileSync(new URL(file, MIGRATIONS), "utf8"));
  return db;
}

function d1Error(error: unknown): Error {
  const message = error instanceof Error ? error.message : String(error);
  const kind = /constraint/i.test(message) ? "SQLITE_CONSTRAINT" : "SQLITE_ERROR";
  return new Error(`D1_ERROR: ${message}: ${kind}`, { cause: error });
}

function bindable(value: unknown, index: number): SQLInputValue {
  if (value === undefined) throw new Error(`D1_TYPE_ERROR: Type 'undefined' not supported for value 'undefined' at index ${index}`);
  if (typeof value === "boolean") return value ? 1 : 0;
  if (value === null || typeof value === "number" || typeof value === "string" || typeof value === "bigint") return value;
  if (value instanceof ArrayBuffer) return new Uint8Array(value);
  if (ArrayBuffer.isView(value)) return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
  throw new Error(`D1_TYPE_ERROR: Type '${typeof value}' not supported for value at index ${index}`);
}

function meta(changes = 0, lastRowId = 0) {
  return {
    duration: 0,
    size_after: 0,
    rows_read: 0,
    rows_written: changes,
    last_row_id: lastRowId,
    changed_db: changes > 0,
    changes,
  };
}

/** Rows from node:sqlite have a null prototype; D1's are plain objects. */
const plain = (row: unknown) => ({ ...(row as Record<string, unknown>) });

class TestStatement {
  readonly #db: TestD1;
  readonly sql: string;
  readonly params: SQLInputValue[];

  constructor(db: TestD1, sql: string, params: SQLInputValue[] = []) {
    this.#db = db;
    this.sql = sql;
    this.params = params;
  }

  bind(...values: unknown[]): TestStatement {
    return new TestStatement(this.#db, this.sql, values.map(bindable));
  }

  #statement(): StatementSync {
    try {
      return this.#db.sqlite.prepare(this.sql);
    } catch (error) {
      throw d1Error(error);
    }
  }

  /** Runs the statement now, as a batch does: rows if it returns any, changes otherwise. */
  execute() {
    this.#db.statements.push(this.sql);
    const statement = this.#statement();
    try {
      if (statement.columns().length > 0) {
        const results = statement.all(...this.params).map(plain);
        return { success: true as const, results, meta: meta() };
      }
      const info = statement.run(...this.params);
      return { success: true as const, results: [], meta: meta(Number(info.changes), Number(info.lastInsertRowid)) };
    } catch (error) {
      throw d1Error(error);
    }
  }

  async first(column?: string): Promise<unknown> {
    const row = this.execute().results[0];
    if (row === undefined) return null;
    return column === undefined ? row : (row[column] ?? null);
  }

  async all() {
    return this.execute();
  }

  async run() {
    return this.execute();
  }

  async raw(options?: { columnNames?: boolean }): Promise<unknown[]> {
    const { results } = this.execute();
    const rows = results.map((row) => Object.values(row));
    if (options?.columnNames) return [Object.keys(results[0] ?? {}), ...rows];
    return rows;
  }
}

export class TestD1 {
  readonly sqlite: DatabaseSync;
  /** Every statement run, in order: lets tests check what reached the database. */
  readonly statements: string[] = [];

  constructor(sqlite: DatabaseSync = migratedSQLite()) {
    this.sqlite = sqlite;
  }

  prepare(sql: string): TestStatement {
    return new TestStatement(this, sql);
  }

  async batch(statements: TestStatement[]) {
    this.sqlite.exec("BEGIN");
    try {
      const results = statements.map((statement) => statement.execute());
      this.sqlite.exec("COMMIT");
      return results;
    } catch (error) {
      this.sqlite.exec("ROLLBACK");
      throw error;
    }
  }

  async exec(sql: string) {
    try {
      this.sqlite.exec(sql);
    } catch (error) {
      throw d1Error(error);
    }
    return { count: sql.split(";").filter((part) => part.trim().length > 0).length, duration: 0 };
  }

  /** This adapter typed as the binding src/ expects. */
  get binding(): D1Database {
    return this as unknown as D1Database;
  }
}
