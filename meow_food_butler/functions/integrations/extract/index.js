/**
 * AI restaurant-name extraction — the real implementation of the Dart
 * `AiAgentService.extractRestaurantName` mock. Given an IG caption + check-in
 * location tag, return a precise "<name> <area>" query for Outscraper, or null.
 *
 * Reuses the chat Gemini keys (`getGeminiKeys`) and one-shot Genkit `generate`
 * with key rotation, so it shares the same quota/rotation behavior as the butler.
 */

const { googleAI } = require("@genkit-ai/googleai");
const logger = require("firebase-functions/logger");

const { getButler } = require("../../agent/butler");
const { getGeminiKeys } = require("../../agent/keys");

function buildPrompt(caption, location) {
  return (
    "你是一個美食達人，請從以下 Instagram 貼文內文與打卡地標中，精準提取出「餐廳名稱」與「所在城市或地區」。\n" +
    `打卡地標: ${location}\n` +
    `內文: ${caption}\n\n` +
    '請只回傳最有可能的餐廳名稱與地區（例如："一蘭拉麵 台北信義店" 或 "鼎泰豐 101"），' +
    '不需要任何額外的解釋或標點符號。如果完全找不到，請回傳 "UNKNOWN"。'
  );
}

/**
 * @returns {Promise<string|null>} the extracted query, or null if the model
 *   couldn't identify a restaurant (or no key worked).
 */
async function extractRestaurantName(caption, location) {
  const keys = await getGeminiKeys();
  if (!keys.length) {
    logger.warn("extractRestaurantName: no Gemini keys available");
    return null;
  }

  const prompt = buildPrompt(caption || "", location || "");
  for (let i = 0; i < keys.length; i += 1) {
    try {
      const { instance } = getButler(keys[i]);
      const res = await instance.generate({
        model: googleAI.model("gemini-2.5-flash"),
        prompt,
      });
      const text = (res.text || "").trim();
      if (!text || text.toUpperCase() === "UNKNOWN") return null;
      return text;
    } catch (err) {
      logger.error("extractRestaurantName generate() failed", {
        keyIndex: i + 1,
        message: err && err.message,
      });
      // Rotate to the next key.
    }
  }
  return null;
}

module.exports = { extractRestaurantName };
