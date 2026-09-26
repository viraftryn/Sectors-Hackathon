# Deploying the backend and running the demo

For whoever deploys the backend and records the demo. Everything here was checked on
2026-09-25 against a Postgres 16 database with the Supabase migration and the real Sectors API.

## 1. Deploy

The image is built from `backend/Dockerfile` (build context: `backend/`). It runs on any container
host that injects a `PORT` variable, and falls back to 8000.

```bash
cd backend
docker build -t invelio-backend .
docker run -p 8000:8000 --env-file .env invelio-backend   # local check
```

Keep **one instance** running. The scoring run lock is per process, so several instances could
each start a scoring run and pay for it.

### Environment variables

Set these in the host's dashboard. Never commit them.

| Variable | Demo value | Notes |
|---|---|---|
| `SECTORS_API_KEY` | the team key | Every real call spends credits |
| `GEMINI_API_KEY` | AI Studio key | Scoring reasoning and chatbot |
| `DATABASE_URL` | Supabase connection string | Must start with `postgresql+asyncpg://` (see below) |
| `USE_MOCK_DATA` | `false` | `true` serves saved sample data, 0 credits |
| `USE_MCP` | `true` for the demo | Chatbot uses the Sectors MCP server; each question spends credits |
| `ENVIRONMENT` | `production` | Turns off SQL logging |
| `CHATBOT_MODEL` | optional | Defaults to `gemini-3.5-flash-lite` |

### Supabase connection string

- Copy it from Supabase: Project Settings → Database → Connection string, and change the prefix
  from `postgresql://` to `postgresql+asyncpg://`.
- Use the **Session pooler** string. The direct connection is IPv6-only on Supabase unless the
  IPv4 add-on is enabled, and many hosts cannot reach IPv6.
- Avoid the **Transaction pooler** (port 6543): it does not support the prepared statements
  asyncpg uses.
- The migration in `supabase/migrations/` must already be applied (the Supabase GitHub Action
  does this on pushes to `main`).

### Check the deployment

```bash
curl https://<your-host>/api/status
# {"status":"ok", ..., "mock_data": false, "sectors_api_calls": 0}
```

Then set the release `baseURL` in `ios/Invelio/Sources/Services/APIClient.swift` to
`https://<your-host>/api`.

## 2. Before recording

Run these once, in order, against the deployed backend. Scores and alerts are stored in
Supabase, so the app shows them instantly afterwards.

| Step | Command | Credits (approx.) |
|---|---|---|
| Score all 10 stocks | `curl -X POST https://<host>/api/scoring/run` | ~45 (takes a few seconds; runs at most once an hour) |
| Scan for alerts | `curl -X POST https://<host>/api/alerts/scan` | ~5 |
| Check scores exist | `curl https://<host>/api/recommendations` | 0 |

While recording:

- **Home / stock detail / market overview:** a few credits at most. Responses are cached for
  5–10 minutes, so reopening screens is free within that window.
- **Chatbot with `USE_MCP=true`:** each question calls Sectors directly (no cache), usually 2–6
  credits. Ask about the 10 tracked tickers only; others are refused before any call is made.
- **Portfolio and alerts:** no Sectors credits.
- **Rehearse with `USE_MCP=false`.** The chatbot then uses the cached REST tools, so practice runs
  cost almost nothing; switch to `true` only for the recorded take.

Check the team key's remaining credits on the Sectors dashboard before the first real run.
Backend testing so far was done on a separate key, so the team budget is untouched by it. A full
rehearsal plus the recording should stay well under 200 credits.

### Chatbot questions that show the agent well

- "How is BBCA performing?"
- "Compare BBRI and BMRI."
- "How is the banking sector doing?"
- "What is moving the market today?"

### Avoid

- Calling `/api/scoring/run` repeatedly. It is throttled, but every real run costs ~45 credits.
- Restarting the server between takes. The Supabase cache survives restarts; the in-memory
  layer does not.
- Asking the chatbot about untracked tickers. It refuses, which looks like a failure on video.

## 3. If something goes wrong

| Symptom | Likely cause | Fix |
|---|---|---|
| `/api/status` shows `"mock_data": true` | `USE_MOCK_DATA` not set to `false` | Set it and redeploy |
| 500 errors on every data screen | `DATABASE_URL` wrong or unreachable | Use the Session pooler string with the `+asyncpg` prefix |
| `DuplicatePreparedStatementError` in logs | Transaction pooler (port 6543) | Switch to the Session pooler |
| Chatbot returns 429 | Gemini free-tier quota reached | Wait for the reset, or enable billing on the AI Studio project |
| Chatbot returns 503 | Gemini overloaded | Retry after a few seconds |
| Recommendations list is empty | Scoring never ran on this database | `POST /api/scoring/run` |
| Market overview shows no movers | Sectors call failed | Backend degrades gracefully; retry in a minute |
