import { DurableObject } from "cloudflare:workers";

export interface ReservationRequest {
  reservationID: string;
  flowID: string;
  installationHash: string;
  worstCaseMicroUSD: number;
  dailyBudgetMicroUSD: number;
  flowBudgetMicroUSD: number;
  maxCallsPerFlow: number;
  maxCallsPerMinute: number;
  nowUnixMilliseconds: number;
}

export interface ReservationResult {
  accepted: boolean;
  code: "accepted" | "duplicate" | "daily_budget" | "flow_budget" | "flow_calls" | "rate_limit" | "circuit_open";
  reservedMicroUSD: number;
  openUntilUnixMilliseconds: number;
}

export type ProviderOutcome = "success" | "transientFailure" | "permanentFailure" | "neutralFailure";

type BudgetRow = {
  spent_micro_usd: number;
  reserved_micro_usd: number;
  failure_count: number;
  open_until_ms: number;
};

type FlowRow = {
  spent_micro_usd: number;
  reserved_micro_usd: number;
  calls: number;
};

type ReservationRow = {
  flow_id: string;
  reserved_micro_usd: number;
  state: string;
};

type RateRow = {
  window_start_ms: number;
  calls: number;
};

export class BudgetLedger extends DurableObject<Cloudflare.Env> {
  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS budget (
          id INTEGER PRIMARY KEY CHECK (id = 1),
          spent_micro_usd INTEGER NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          failure_count INTEGER NOT NULL,
          open_until_ms INTEGER NOT NULL
        );
        INSERT OR IGNORE INTO budget VALUES (1, 0, 0, 0, 0);

        CREATE TABLE IF NOT EXISTS flows (
          flow_id TEXT PRIMARY KEY,
          spent_micro_usd INTEGER NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          calls INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS reservations (
          reservation_id TEXT PRIMARY KEY,
          flow_id TEXT NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          state TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS rates (
          installation_hash TEXT PRIMARY KEY,
          window_start_ms INTEGER NOT NULL,
          calls INTEGER NOT NULL
        );
      `);
    });
  }

  reserve(request: ReservationRequest): ReservationResult {
    validateReservationRequest(request);
    const existing = this.ctx.storage.sql.exec<{ state: string }>(
      "SELECT state FROM reservations WHERE reservation_id = ?",
      request.reservationID,
    ).toArray()[0];
    if (existing !== undefined) return rejected("duplicate");

    const budget = this.ctx.storage.sql.exec<BudgetRow>(
      "SELECT spent_micro_usd, reserved_micro_usd, failure_count, open_until_ms FROM budget WHERE id = 1",
    ).one();
    if (budget.open_until_ms > request.nowUnixMilliseconds) {
      return rejected("circuit_open", budget.open_until_ms);
    }
    if (budget.spent_micro_usd + budget.reserved_micro_usd + request.worstCaseMicroUSD > request.dailyBudgetMicroUSD) {
      return rejected("daily_budget");
    }

    this.ctx.storage.sql.exec(
      "INSERT OR IGNORE INTO flows VALUES (?, 0, 0, 0)",
      request.flowID,
    );
    const flow = this.ctx.storage.sql.exec<FlowRow>(
      "SELECT spent_micro_usd, reserved_micro_usd, calls FROM flows WHERE flow_id = ?",
      request.flowID,
    ).one();
    if (flow.calls >= request.maxCallsPerFlow) return rejected("flow_calls");
    if (flow.spent_micro_usd + flow.reserved_micro_usd + request.worstCaseMicroUSD > request.flowBudgetMicroUSD) {
      return rejected("flow_budget");
    }

    const minuteStart = Math.floor(request.nowUnixMilliseconds / 60_000) * 60_000;
    const rate = this.ctx.storage.sql.exec<RateRow>(
      "SELECT window_start_ms, calls FROM rates WHERE installation_hash = ?",
      request.installationHash,
    ).toArray()[0];
    const nextRate = rate === undefined || rate.window_start_ms !== minuteStart ? 1 : rate.calls + 1;
    if (nextRate > request.maxCallsPerMinute) return rejected("rate_limit");

    this.ctx.storage.sql.exec(
      `INSERT INTO rates (installation_hash, window_start_ms, calls) VALUES (?, ?, ?)
       ON CONFLICT(installation_hash) DO UPDATE SET window_start_ms = excluded.window_start_ms, calls = excluded.calls`,
      request.installationHash,
      minuteStart,
      nextRate,
    );
    this.ctx.storage.sql.exec(
      "INSERT INTO reservations VALUES (?, ?, ?, 'reserved', ?)",
      request.reservationID,
      request.flowID,
      request.worstCaseMicroUSD,
      request.nowUnixMilliseconds,
    );
    this.ctx.storage.sql.exec(
      "UPDATE budget SET reserved_micro_usd = reserved_micro_usd + ? WHERE id = 1",
      request.worstCaseMicroUSD,
    );
    this.ctx.storage.sql.exec(
      "UPDATE flows SET reserved_micro_usd = reserved_micro_usd + ?, calls = calls + 1 WHERE flow_id = ?",
      request.worstCaseMicroUSD,
      request.flowID,
    );

    return {
      accepted: true,
      code: "accepted",
      reservedMicroUSD: request.worstCaseMicroUSD,
      openUntilUnixMilliseconds: 0,
    };
  }

  settle(
    reservationID: string,
    actualMicroUSD: number,
    outcome: ProviderOutcome,
    nowUnixMilliseconds: number,
  ): boolean {
    const reservation = this.reservation(reservationID);
    if (reservation === undefined || reservation.state !== "reserved") return false;
    if (!Number.isInteger(actualMicroUSD) || actualMicroUSD < 0 || actualMicroUSD > reservation.reserved_micro_usd) {
      throw new Error("Settlement is outside its reservation.");
    }

    this.ctx.storage.sql.exec(
      "UPDATE reservations SET state = 'settled' WHERE reservation_id = ?",
      reservationID,
    );
    this.ctx.storage.sql.exec(
      `UPDATE budget
       SET reserved_micro_usd = reserved_micro_usd - ?, spent_micro_usd = spent_micro_usd + ?
       WHERE id = 1`,
      reservation.reserved_micro_usd,
      actualMicroUSD,
    );
    this.ctx.storage.sql.exec(
      `UPDATE flows
       SET reserved_micro_usd = reserved_micro_usd - ?, spent_micro_usd = spent_micro_usd + ?
       WHERE flow_id = ?`,
      reservation.reserved_micro_usd,
      actualMicroUSD,
      reservation.flow_id,
    );
    this.recordCircuitOutcome(outcome, nowUnixMilliseconds);
    return true;
  }

  release(reservationID: string): boolean {
    const reservation = this.reservation(reservationID);
    if (reservation === undefined || reservation.state !== "reserved") return false;
    this.ctx.storage.sql.exec(
      "UPDATE reservations SET state = 'released' WHERE reservation_id = ?",
      reservationID,
    );
    this.ctx.storage.sql.exec(
      "UPDATE budget SET reserved_micro_usd = reserved_micro_usd - ? WHERE id = 1",
      reservation.reserved_micro_usd,
    );
    this.ctx.storage.sql.exec(
      "UPDATE flows SET reserved_micro_usd = reserved_micro_usd - ? WHERE flow_id = ?",
      reservation.reserved_micro_usd,
      reservation.flow_id,
    );
    return true;
  }

  private reservation(reservationID: string): ReservationRow | undefined {
    return this.ctx.storage.sql.exec<ReservationRow>(
      "SELECT flow_id, reserved_micro_usd, state FROM reservations WHERE reservation_id = ?",
      reservationID,
    ).toArray()[0];
  }

  private recordCircuitOutcome(outcome: ProviderOutcome, now: number): void {
    const budget = this.ctx.storage.sql.exec<BudgetRow>(
      "SELECT spent_micro_usd, reserved_micro_usd, failure_count, open_until_ms FROM budget WHERE id = 1",
    ).one();
    if (outcome === "success") {
      this.ctx.storage.sql.exec("UPDATE budget SET failure_count = 0, open_until_ms = 0 WHERE id = 1");
      return;
    }
    if (outcome === "neutralFailure") return;
    if (outcome === "permanentFailure") {
      this.ctx.storage.sql.exec(
        "UPDATE budget SET failure_count = failure_count + 1, open_until_ms = ? WHERE id = 1",
        now + 300_000,
      );
      return;
    }

    const failures = budget.failure_count + 1;
    const openUntil = failures >= 3 ? now + 60_000 : 0;
    this.ctx.storage.sql.exec(
      "UPDATE budget SET failure_count = ?, open_until_ms = ? WHERE id = 1",
      failures,
      openUntil,
    );
  }
}

function validateReservationRequest(request: ReservationRequest): void {
  const integers = [
    request.worstCaseMicroUSD,
    request.dailyBudgetMicroUSD,
    request.flowBudgetMicroUSD,
    request.maxCallsPerFlow,
    request.maxCallsPerMinute,
    request.nowUnixMilliseconds,
  ];
  if (!request.reservationID || !request.flowID || !request.installationHash) {
    throw new Error("Reservation identifiers are required.");
  }
  if (integers.some((value) => !Number.isInteger(value) || value < 0)) {
    throw new Error("Reservation limits must be nonnegative integers.");
  }
}

function rejected(
  code: Exclude<ReservationResult["code"], "accepted">,
  openUntilUnixMilliseconds = 0,
): ReservationResult {
  return { accepted: false, code, reservedMicroUSD: 0, openUntilUnixMilliseconds };
}
