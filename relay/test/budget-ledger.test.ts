import { env } from "cloudflare:workers";
import { describe, expect, it } from "vitest";

describe("atomic budget ledger", () => {
  it("rejects a zero daily budget before reserving any spend", async () => {
    const ledger = env.BUDGET_LEDGER.getByName("zero-budget");
    const result = await ledger.reserve(reservation("zero", 0, 100_000));
    expect(result).toMatchObject({ accepted: false, code: "daily_budget" });
  });

  it("enforces flow budget and duplicate reservation IDs", async () => {
    const ledger = env.BUDGET_LEDGER.getByName("flow-budget");
    const first = await ledger.reserve(reservation("one", 100_000, 20_000));
    expect(first.accepted).toBe(true);
    const duplicate = await ledger.reserve(reservation("one", 100_000, 20_000));
    expect(duplicate.code).toBe("duplicate");
    const second = await ledger.reserve(reservation("two", 100_000, 20_000));
    expect(second.code).toBe("flow_budget");
  });

  it("opens the circuit after three transient upstream failures", async () => {
    const ledger = env.BUDGET_LEDGER.getByName("circuit");
    const now = 1_800_000_000_000;
    for (let index = 0; index < 3; index += 1) {
      const id = `failure-${index}`;
      const accepted = await ledger.reserve(reservation(id, 1_000_000, 1_000_000, now + index));
      expect(accepted.accepted).toBe(true);
      expect(await ledger.settle(id, 18_000, "transientFailure", now + index)).toBe(true);
    }
    const blocked = await ledger.reserve(reservation("blocked", 1_000_000, 1_000_000, now + 10));
    expect(blocked.code).toBe("circuit_open");
    expect(blocked.openUntilUnixMilliseconds).toBeGreaterThan(now);
  });
});

function reservation(
  id: string,
  dailyBudgetMicroUSD: number,
  flowBudgetMicroUSD: number,
  nowUnixMilliseconds = 1_800_000_000_000,
) {
  return {
    reservationID: id,
    flowID: "flow_fixture_001",
    installationHash: "hash_fixture_001",
    worstCaseMicroUSD: 18_000,
    dailyBudgetMicroUSD,
    flowBudgetMicroUSD,
    maxCallsPerFlow: 4,
    maxCallsPerMinute: 4,
    nowUnixMilliseconds,
  };
}
