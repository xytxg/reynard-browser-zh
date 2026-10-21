#!/usr/bin/env node
// Compare public upstream catalogs to this fork without automatically altering translations.
// Runs on a scheduled or manual GitHub Actions job. Node.js 20+ only.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { writeFileSync } = fs;
const base = path.resolve(__dirname, "../..");
const catalogs = [
  "browser/Reynard/Resources/Localizable.xcstrings",
  "browser/Reynard/Client/Interface/Addons/AddonLocalizable.xcstrings",
  "browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings",
  "browser/Reynard/Client/Interface/ContentView/WebContentErrorLocalizable.xcstrings",
];
const branch = process.env.UPSTREAM_REF || "main";
if (!/^[a-zA-Z0-9_.\/-]+$/.test(branch) || branch.includes("..")) {
  throw new Error("Invalid upstream ref");
}
const value = (entry, locale) => entry?.localizations?.[locale]?.stringUnit?.value ??
  entry?.localizations?.[locale]?.variations?.plural?.other?.stringUnit?.value;
async function loadPublic(url) {
  const res = await fetch(url, { headers: { "User-Agent": "Reynard-i18n-audit" }, signal: AbortSignal.timeout(25000) });
  if (!res.ok) throw new Error("Upstream request returned " + res.status);
  return JSON.parse(await res.text());
}
(async () => {
  const report = ["# Reynard upstream localization report", "",
    "Upstream: `minh-ton/reynard-browser@`" + branch, "",
    "Report only; no translations or releases were automatically modified.", ""];
  let total = 0;
  for (const file of catalogs) {
    const local = JSON.parse(fs.readFileSync(path.join(base, file), "utf8"));
    const upstream = await loadPublic("https://raw.githubusercontent.com/minh-ton/reynard-browser/" + branch + "/" + file);
    const missing = [], needsReview = [], changedEnglish = [], newChineseUpstream = [];
    for (const [key, entry] of Object.entries(upstream.strings)) {
      const ours = local.strings[key];
      if (!ours) { missing.push(key); continue; }
      const theirsZh = value(entry, "zh-Hans");
      const oursZh = value(ours, "zh-Hans");
      if (!oursZh?.trim()) needsReview.push(key);
      const upstreamEnglish = value(entry, "en") ?? key;
      const ourEnglish = value(ours, "en") ?? key;
      if (upstreamEnglish !== ourEnglish) changedEnglish.push(key);
      if (theirsZh && theirsZh !== oursZh) newChineseUpstream.push(key);
    }
    total += missing.length + needsReview.length + changedEnglish.length + newChineseUpstream.length;
    report.push("## " + file, "",
      "| Check | Count |", "| --- | ---: |",
      "| New upstream keys missing in fork | " + missing.length + " |",
      "| Empty Simplified Chinese values | " + needsReview.length + " |",
      "| Changed English reference text | " + changedEnglish.length + " |",
      "| Different upstream Chinese translations | " + newChineseUpstream.length + " |", "");
    for (const [label, keys] of [
      ["Missing upstream keys", missing], ["Missing Chinese translations", needsReview],
      ["Updated English strings", changedEnglish], ["Updated upstream Chinese strings", newChineseUpstream]
    ]) {
      if (keys.length) report.push("**" + label + "**", "",
        ...keys.slice(0, 35).map(k => "- `" + k.replaceAll("\n", " ↵ ").replaceAll("`", "'") + "`"),
        keys.length > 35 ? "- … " + (keys.length - 35) + " more" : "", "");
    }
  }
  report.push("**Manual review required:** " + total + " differences (categories may overlap).", "");
  const markdown = report.join("\n");
  writeFileSync(path.join(base, "upstream-localization-report.md"), markdown);
  if (process.env.GITHUB_STEP_SUMMARY) {
    fs.appendFileSync(process.env.GITHUB_STEP_SUMMARY, markdown + "\n");
  }
  console.log(markdown.slice(0, 11000));
})().catch(error => { console.error("Localization upstream check failed:", error.message); process.exitCode = 1; });
