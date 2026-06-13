/**
 * The Genkit "butler" instance: persona, lazily-initialized model client, and
 * system-prompt assembly (persona + current time + recalled memory).
 *
 * The instance + tool refs are cached across warm invocations; tools must be
 * defined on the SAME instance that runs the flow.
 */

const { genkit } = require("genkit");
const { googleAI } = require("@genkit-ai/googleai");

const { resolvePlacesApiKey } = require("../config");
const { registerTools } = require("../skills");

// Cat-butler persona + how to drive the L1→L2 agent flow (see agent_design.md).
const SYSTEM_PROMPT = [
  "You are the Meow Food Butler: a wise, friendly cat butler who recommends food spots.",
  "Speak in a cat-like tone — end sentences with 'meow', 'nya', or 'prrr', varying with the mood.",
  "When the user asks where they are (or you need their current position), call the",
  "whereAmI tool. If it returns permissionGranted=false, gently ask them to enable",
  "location permission. When it returns nearby places, do NOT assert a single spot —",
  "tell them the most likely one first and offer the other candidates to pick from.",
  "You also plan in two layers. L1 (Planning): call findFreeTime, recallMemory, then searchSpots",
  "to build a candidate list. L2 (Execution): use routeDistance to keep only spots within the",
  "user's max walk time, recommend one, and after a visit use draftExperience to write it up.",
  "Memory: when the user shares a durable preference or fact (a cuisine they love/hate, a",
  "constraint, a place they enjoyed), call the remember tool to save it. Use recallMemory to",
  "personalize. Always respect the user's preferences and constraints from recallMemory.",
  "Keep replies concise and end with a cat sound.",
].join(" ");

// Cache the Genkit instance + tool refs across warm invocations.
let _butler = null;
function getButler(apiKey) {
  if (_butler) return _butler;
  // Pass the key explicitly rather than relying on process.env so the binding is
  // unambiguous regardless of how the secret is surfaced.
  const instance = genkit({ plugins: [googleAI({ apiKey })] });
  const tools = registerTools(instance, { placesApiKey: resolvePlacesApiKey() });
  _butler = { instance, tools };
  return _butler;
}

/**
 * Assemble the full system prompt for a request: persona + a glanceable clock
 * reading + any recalled long-term memory about this user.
 *
 * @param {object} opts
 * @param {object} [opts.now] - { local?: string, iso?: string } device time.
 * @param {Array<{text:string, kind?:string}>} [opts.recalled] - top-k memories.
 */
function buildSystem({ now, recalled } = {}) {
  // The model has no clock of its own. Give it a plain wall-clock reading so it
  // can let the time of day shape suggestions, the way a person would.
  const clock =
    (now && (now.local || now.iso)) || `${new Date().toISOString()} (UTC)`;
  const timeLine =
    `Right now it is ${clock} for the user. Read it like a clock and let the ` +
    `time of day shape your suggestions — late morning -> brunch, around noon -> ` +
    `lunch, evening -> dinner, late night -> a snack.`;

  let memoryLine = "";
  if (Array.isArray(recalled) && recalled.length) {
    const bullets = recalled.map((m) => `- ${m.text}`).join("\n");
    memoryLine =
      `\nWhat you remember about this user (use it naturally, don't recite it):\n${bullets}`;
  }

  return `${SYSTEM_PROMPT}\n${timeLine}${memoryLine}`;
}

module.exports = { getButler, buildSystem, SYSTEM_PROMPT };
