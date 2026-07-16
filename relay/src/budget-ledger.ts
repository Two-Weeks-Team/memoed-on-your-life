import { DurableObject } from "cloudflare:workers";

export interface ReservationRequest {
  reservationID: string;
  dateKey: string;
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
  code: "accepted" | "duplicate" | "daily_budget" | "flow_budget" | "flow_calls" | "flow_owner" | "rate_limit" | "circuit_open";
  reservedMicroUSD: number;
  openUntilUnixMilliseconds: number;
}

export interface InstallationPurgeResult {
  reservations: number;
  flows: number;
  rateWindows: number;
}

export type ProviderOutcome = "success" | "transientFailure" | "permanentFailure" | "neutralFailure";

type BudgetRow = {
  spent_micro_usd: number;
  reserved_micro_usd: number;
  failure_count: number;
  open_until_ms: number;
};

type FlowRow = {
  installation_hash: string;
  spent_micro_usd: number;
  reserved_micro_usd: number;
  calls: number;
};

type ReservationRow = {
  reservation_id: string;
  date_key: string;
  flow_id: string;
  installation_hash: string;
  reserved_micro_usd: number;
  state: string;
};

type RateRow = {
  window_start_ms: number;
  calls: number;
};

type CountRow = { count: number };

export class BudgetLedger extends DurableObject<Cloudflare.Env> {
  constructor(ctx: DurableObjectState, env: Cloudflare.Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS budget (
          date_key TEXT PRIMARY KEY,
          spent_micro_usd INTEGER NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          failure_count INTEGER NOT NULL,
          open_until_ms INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS flows (
          date_key TEXT NOT NULL,
          flow_id TEXT NOT NULL,
          installation_hash TEXT NOT NULL,
          spent_micro_usd INTEGER NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          calls INTEGER NOT NULL,
          PRIMARY KEY (date_key, flow_id)
        );

        CREATE TABLE IF NOT EXISTS reservations (
          reservation_id TEXT PRIMARY KEY,
          date_key TEXT NOT NULL,
          flow_id TEXT NOT NULL,
          installation_hash TEXT NOT NULL,
          reserved_micro_usd INTEGER NOT NULL,
          state TEXT NOT NULL,
          created_at_ms INTEGER NOT NULL
        );

        CREATE TABLE IF NOT EXISTS rates (
          date_key TEXT NOT NULL,
          installation_hash TEXT NOT NULL,
          window_start_ms INTEGER NOT NULL,
          calls INTEGER NOT NULL,
          PRIMARY KEY (date_key, installation_hash)
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

    this.ctx.storage.sql.exec(
      "INSERT OR IGNORE INTO budget VALUES (?, 0, 0, 0, 0)",
      request.dateKey,
    );
    const budget = this.ctx.storage.sql.exec<BudgetRow>(
      "SELECT spent_micro_usd, reserved_micro_usd, failure_count, open_until_ms FROM budget WHERE date_key = ?",
      request.dateKey,
    ).one();
    if (budget.open_until_ms > request.nowUnixMilliseconds) {
      return rejected("circuit_open", budget.open_until_ms);
    }
    if (budget.spent_micro_usd + budget.reserved_micro_usd + request.worstCaseMicroUSD > request.dailyBudgetMicroUSD) {
      return rejected("daily_budget");
    }

    this.ctx.storage.sql.exec(
      "INSERT OR IGNORE INTO flows VALUES (?, ?, ?, 0, 0, 0)",
      request.dateKey,
      request.flowID,
      request.installationHash,
    );
    const flow = this.ctx.storage.sql.exec<FlowRow>(
      `SELECT installation_hash, spent_micro_usd, reserved_micro_usd, calls
       FROM flows WHERE date_key = ? AND flow_id = ?`,
      request.dateKey,
      request.flowID,
    ).one();
    if (flow.installation_hash !== request.installationHash) return rejected("flow_owner");
    if (flow.calls >= request.maxCallsPerFlow) return rejected("flow_calls");
    if (flow.spent_micro_usd + flow.reserved_micro_usd + request.worstCaseMicroUSD > request.flowBudgetMicroUSD) {
      return rejected("flow_budget");
    }

    const minuteStart = Math.floor(request.nowUnixMilliseconds / 60_000) * 60_000;
    const rate = this.ctx.storage.sql.exec<RateRow>(
      "SELECT window_start_ms, calls FROM rates WHERE date_key = ? AND installation_hash = ?",
      request.dateKey,
      request.installationHash,
    ).toArray()[0];
    const nextRate = rate === undefined || rate.window_start_ms !== minuteStart ? 1 : rate.calls + 1;
    if (nextRate > request.maxCallsPerMinute) return rejected("rate_limit");

    this.ctx.storage.sql.exec(
      `INSERT INTO rates (date_key, installation_hash, window_start_ms, calls) VALUES (?, ?, ?, ?)
       ON CONFLICT(date_key, installation_hash)
       DO UPDATE SET window_start_ms = excluded.window_start_ms, calls = excluded.calls`,
      request.dateKey,
      request.installationHash,
      minuteStart,
      nextRate,
    );
    this.ctx.storage.sql.exec(
      "INSERT INTO reservations VALUES (?, ?, ?, ?, ?, 'reserved', ?)",
      request.reservationID,
      request.dateKey,
      request.flowID,
      request.installationHash,
      request.worstCaseMicroUSD,
      request.nowUnixMilliseconds,
    );
    this.ctx.storage.sql.exec(
      "UPDATE budget SET reserved_micro_usd = reserved_micro_usd + ? WHERE date_key = ?",
      request.worstCaseMicroUSD,
      request.dateKey,
    );
    this.ctx.storage.sql.exec(
      `UPDATE flows SET reserved_micro_usd = reserved_micro_usd + ?, calls = calls + 1
       WHERE date_key = ? AND flow_id = ?`,
      request.worstCaseMicroUSD,
      request.dateKey,
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
       WHERE date_key = ?`,
      reservation.reserved_micro_usd,
      actualMicroUSD,
      reservation.date_key,
    );
    this.ctx.storage.sql.exec(
      `UPDATE flows
       SET reserved_micro_usd = reserved_micro_usd - ?, spent_micro_usd = spent_micro_usd + ?
       WHERE date_key = ? AND flow_id = ?`,
      reservation.reserved_micro_usd,
      actualMicroUSD,
      reservation.date_key,
      reservation.flow_id,
    );
    this.recordCircuitOutcome(reservation.date_key, outcome, nowUnixMilliseconds);
    return true;
  }

  release(reservationID: string): boolean {
    const reservation = this.reservation(reservationID);
    if (reservation === undefined || reservation.state !== "reserved") return false;
    this.ctx.storage.sql.exec(
      "UPDATE reservations SET state = 'released' WHERE reservation_id = ?",
      reservationID,
    );
    this.releaseReservedAmount(reservation);
    return true;
  }

  purgeInstallation(installationHash: string): InstallationPurgeResult {
    if (!/^[a-f0-9]{64}$/.test(installationHash)) {
      throw new Error("Installation hash is invalid.");
    }
    const reservations = this.ctx.storage.sql.exec<ReservationRow>(
      `SELECT reservation_id, date_key, flow_id, installation_hash, reserved_micro_usd, state
       FROM reservations WHERE installation_hash = ?`,
      installationHash,
    ).toArray();
    const flowCount = this.ctx.storage.sql.exec<CountRow>(
      "SELECT COUNT(*) AS count FROM flows WHERE installation_hash = ?",
      installationHash,
    ).one().count;
    const rateCount = this.ctx.storage.sql.exec<CountRow>(
      "SELECT COUNT(*) AS count FROM rates WHERE installation_hash = ?",
      installationHash,
    ).one().count;

    const anonymousInstallationHash = "0".repeat(64);
    for (const reservation of reservations.filter((item) => item.state === "reserved")) {
      const anonymousFlowID = `purged:${crypto.randomUUID()}`;
      this.ctx.storage.sql.exec(
        "INSERT INTO flows VALUES (?, ?, ?, 0, ?, 0)",
        reservation.date_key,
        anonymousFlowID,
        anonymousInstallationHash,
        reservation.reserved_micro_usd,
      );
      this.ctx.storage.sql.exec(
        `UPDATE reservations SET flow_id = ?, installation_hash = ?
         WHERE reservation_id = ? AND installation_hash = ? AND state = 'reserved'`,
        anonymousFlowID,
        anonymousInstallationHash,
        reservation.reservation_id,
        installationHash,
      );
    }
    this.ctx.storage.sql.exec("DELETE FROM reservations WHERE installation_hash = ?", installationHash);
    this.ctx.storage.sql.exec("DELETE FROM flows WHERE installation_hash = ?", installationHash);
    this.ctx.storage.sql.exec("DELETE FROM rates WHERE installation_hash = ?", installationHash);
    return { reservations: reservations.length, flows: flowCount, rateWindows: rateCount };
  }

  private releaseReservedAmount(reservation: ReservationRow): void {
    this.ctx.storage.sql.exec(
      "UPDATE budget SET reserved_micro_usd = reserved_micro_usd - ? WHERE date_key = ?",
      reservation.reserved_micro_usd,
      reservation.date_key,
    );
    this.ctx.storage.sql.exec(
      `UPDATE flows SET reserved_micro_usd = reserved_micro_usd - ?
       WHERE date_key = ? AND flow_id = ?`,
      reservation.reserved_micro_usd,
      reservation.date_key,
      reservation.flow_id,
    );
  }

  private reservation(reservationID: string): ReservationRow | undefined {
    return this.ctx.storage.sql.exec<ReservationRow>(
      `SELECT reservation_id, date_key, flow_id, installation_hash, reserved_micro_usd, state
       FROM reservations WHERE reservation_id = ?`,
      reservationID,
    ).toArray()[0];
  }

  private recordCircuitOutcome(dateKey: string, outcome: ProviderOutcome, now: number): void {
    const budget = this.ctx.storage.sql.exec<BudgetRow>(
      `SELECT spent_micro_usd, reserved_micro_usd, failure_count, open_until_ms
       FROM budget WHERE date_key = ?`,
      dateKey,
    ).one();
    if (outcome === "success") {
      this.ctx.storage.sql.exec(
        "UPDATE budget SET failure_count = 0, open_until_ms = 0 WHERE date_key = ?",
        dateKey,
      );
      return;
    }
    if (outcome === "neutralFailure") return;
    if (outcome === "permanentFailure") {
      this.ctx.storage.sql.exec(
        `UPDATE budget SET failure_count = failure_count + 1, open_until_ms = ?
         WHERE date_key = ?`,
        now + 300_000,
        dateKey,
      );
      return;
    }

    const failures = budget.failure_count + 1;
    const openUntil = failures >= 3 ? now + 60_000 : 0;
    this.ctx.storage.sql.exec(
      "UPDATE budget SET failure_count = ?, open_until_ms = ? WHERE date_key = ?",
      failures,
      openUntil,
      dateKey,
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
  if (!/^\d{4}-\d{2}-\d{2}$/.test(request.dateKey)) {
    throw new Error("Reservation date is invalid.");
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
