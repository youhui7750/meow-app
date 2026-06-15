/**
 * Apify Instagram scraper — server-side port of the Dart `ApifyService`.
 *
 *   fetchIgCaptionAndLocation(igUrl) -> { caption, location } | null
 *
 * Starts an actor run, polls until it finishes, then reads the first dataset item.
 * The poll loop is capped so we fail cleanly before the Cloud Function deadline
 * (the callable sets timeoutSeconds; keep MAX_POLLS * POLL_MS comfortably under it).
 */

const logger = require("firebase-functions/logger");

const { getApifyToken } = require("../keys");

const ACTOR_ID = "apify~instagram-scraper";
const POLL_MS = 3 * 1000;
const MAX_POLLS = 80; // ~4 min ceiling
const TERMINAL_FAIL = new Set(["FAILED", "ABORTED", "TIMED-OUT"]);

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function fetchIgCaptionAndLocation(igUrl) {
  const token = await getApifyToken();
  if (!token) {
    logger.warn("apify: no APIFY_TOKEN configured");
    return null;
  }

  // 1. Start the actor run.
  const startRes = await fetch(
    `https://api.apify.com/v2/acts/${ACTOR_ID}/runs?token=${token}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        directUrls: [igUrl],
        resultsType: "posts",
        resultsLimit: 1,
        addParentData: false,
      }),
    },
  );
  if (startRes.status !== 200 && startRes.status !== 201) {
    logger.error("apify: start run failed", { status: startRes.status });
    return null;
  }
  const runId = (await startRes.json()).data.id;

  // 2. Poll for completion.
  for (let i = 0; i < MAX_POLLS; i += 1) {
    await sleep(POLL_MS);
    const statusRes = await fetch(
      `https://api.apify.com/v2/actor-runs/${runId}?token=${token}`,
    );
    if (!statusRes.ok) continue;

    const data = (await statusRes.json()).data;
    const status = data.status;
    if (status === "SUCCEEDED") {
      // 3. Read the result dataset.
      const itemsRes = await fetch(
        `https://api.apify.com/v2/datasets/${data.defaultDatasetId}/items?token=${token}&format=json`,
      );
      const items = await itemsRes.json();
      if (Array.isArray(items) && items.length) {
        return {
          caption: items[0].caption ?? "",
          location: items[0].locationName ?? "",
        };
      }
      return null;
    }
    if (TERMINAL_FAIL.has(status)) {
      logger.warn("apify: run ended unsuccessfully", { status });
      return null;
    }
  }

  logger.warn("apify: run did not finish within poll budget", { runId });
  return null;
}

module.exports = { fetchIgCaptionAndLocation };
