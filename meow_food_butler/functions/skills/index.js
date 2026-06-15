/**
 * Skill registry.
 *
 * Each skill lives in its own folder (`skills/<name>/index.js`) and exports a
 * `define<Name>(ai, opts)` factory returning a Genkit tool. This aggregator
 * composes them into the array passed to `generate()`. Tools must be defined on
 * the SAME Genkit instance that runs the flow, so this stays a factory.
 */

const { defineWhereAmI } = require("./where-am-i");
const { defineFindFreeTime } = require("./find-free-time");
const { defineRecallMemory } = require("./recall-memory");
const { defineRemember } = require("./remember");
const { defineForget } = require("./forget");
const { defineSetPreference } = require("./set-preference");
const { defineSearchSpots } = require("./search-spots");
const { defineSearchMyPlaces } = require("./search-my-places");
const { defineRouteDistance } = require("./route-distance");
const { defineDraftExperience } = require("./draft-experience");
const { defineViewDiningLog } = require("./view-dining-log");

/**
 * Register all skills on a Genkit instance.
 * @param {import('genkit').Genkit} ai
 * @param {{ placesApiKey?: string }} [opts]
 * @returns the array of tool refs to pass to `generate({ tools })`.
 */
function registerTools(ai, opts = {}) {
  return [
    defineWhereAmI(ai, { placesApiKey: opts.placesApiKey || "" }),
    defineFindFreeTime(ai),
    defineRecallMemory(ai),
    defineRemember(ai),
    defineForget(ai),
    defineSetPreference(ai),
    defineSearchMyPlaces(ai),
    defineSearchSpots(ai, { placesApiKey: opts.placesApiKey || "" }),
    defineRouteDistance(ai),
    defineDraftExperience(ai),
    defineViewDiningLog(ai),
  ];
}

module.exports = { registerTools };
