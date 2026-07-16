# Relay contract

This Cloudflare Worker is the only component permitted to hold an OpenAI credential. The iOS app sends a bounded evidence packet to `/v1/synthesize` and accepts only a versioned, evidence-bound response for `gpt-5.4-mini`.

## Safe local verification

Node.js 24 is the CI baseline. All dependencies are exactly pinned in `package-lock.json`.

```bash
npm ci
npm run check
npm test
npm run dry-run
```

These commands compile the Worker, regenerate and compare bindings, run the Cloudflare Workers test pool, and build a deployment bundle. They do not deploy or call OpenAI.

## Fail-closed defaults

`wrangler.jsonc` commits these independent gates:

- `OPENAI_LIVE_API_ENABLED=false`
- `OPENAI_DAILY_BUDGET_MICRO_USD=0`
- `OPENAI_FLOW_BUDGET_MICRO_USD=0`

Any closed gate returns `503 live_api_disabled` before the Worker reads `OPENAI_API_KEY`. `.dev.vars.example` and the repository `.env.example` contain names only; real values belong only in ignored local files or the deployment platform's secret store.

## Provider contract

- Endpoint: `POST /v1/responses`
- Model allowlist: `gpt-5.4-mini` only
- Storage request: `store: false`
- Output: strict JSON Schema, non-streaming, at most 2,000 tokens
- Input: at most 12 excerpts and 6,000 UTF-8 evidence bytes
- Timeout: at most 20 seconds
- Retry: at most once, only for 429 or 5xx
- Response body: at most 128 KiB
- Claim integrity: every non-Unknown claim must cite an ID in the request packet
- Challenge: requires a structured prior judgment and an independent counterevidence packet

The implementation follows the official [GPT-5.4 mini model contract](https://developers.openai.com/api/docs/models/gpt-5.4-mini), [Structured Outputs guide](https://developers.openai.com/api/docs/guides/structured-outputs), [Cloudflare Workers best practices](https://developers.cloudflare.com/workers/best-practices/workers-best-practices/), and [Workers Vitest integration](https://developers.cloudflare.com/workers/testing/vitest-integration/write-your-first-test/).

Live provider behavior is deliberately unclaimed: no credentialed request has been authorized or executed.
