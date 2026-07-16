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

  it("purges installation-linked flow, reservation, and rate identifiers without erasing aggregate spend", async () => {
    const ledger = env.BUDGET_LEDGER.getByName("privacy-purge");
    const request = reservation("privacy", 1_000_000, 1_000_000);
    const accepted = await ledger.reserve(request);
    expect(accepted.accepted).toBe(true);
    expect(await ledger.settle("privacy", 9_000, "success", request.nowUnixMilliseconds)).toBe(true);

    const deleted = await ledger.purgeInstallation("a".repeat(64));
    expect(deleted).toEqual({ reservations: 1, flows: 1, rateWindows: 1 });
    expect(await ledger.settle("privacy", 9_000, "success", request.nowUnixMilliseconds)).toBe(false);

    const replacement = await ledger.reserve({
      ...reservation("privacy-replacement", 9_000, 9_000),
      installationHash: "b".repeat(64),
      flowID: "replacement_flow",
    });
    expect(replacement).toMatchObject({ accepted: false, code: "daily_budget" });
  });

  it("anonymizes an in-flight reservation while preserving settlement and the global cost ceiling", async () => {
    const ledger = env.BUDGET_LEDGER.getByName("privacy-purge-reserved");
    const accepted = await ledger.reserve(reservation("reserved", 18_000, 18_000));
    expect(accepted.accepted).toBe(true);

    const deleted = await ledger.purgeInstallation("a".repeat(64));
    expect(deleted).toEqual({ reservations: 1, flows: 1, rateWindows: 1 });

    const replacement = await ledger.reserve({
      ...reservation("after-purge", 18_000, 18_000),
      installationHash: "b".repeat(64),
      flowID: "after_purge_flow",
    });
    expect(replacement).toMatchObject({ accepted: false, code: "daily_budget" });
    expect(await ledger.settle("reserved", 9_000, "success", 1_800_000_000_100)).toBe(true);

    const afterSettlement = await ledger.reserve({
      ...reservation("after-settlement", 27_000, 18_000),
      installationHash: "b".repeat(64),
      flowID: "after_settlement_flow",
    });
    expect(afterSettlement.accepted).toBe(true);
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
    dateKey: "2027-01-15",
    flowID: "flow_fixture_001",
    installationHash: "a".repeat(64),
    worstCaseMicroUSD: 18_000,
    dailyBudgetMicroUSD,
    flowBudgetMicroUSD,
    maxCallsPerFlow: 4,
    maxCallsPerMinute: 4,
    nowUnixMilliseconds,
  };
}
