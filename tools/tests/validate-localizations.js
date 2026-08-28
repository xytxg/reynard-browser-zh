#!/usr/bin/env node

const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "../..");
const mainCatalogPath = path.join(root, "browser/Reynard/Resources/Localizable.xcstrings");
const addonCatalogPath = path.join(
  root,
  "browser/Reynard/Client/Interface/Addons/AddonLocalizable.xcstrings"
);
const settingsCatalogPath = path.join(
  root,
  "browser/Reynard/Client/Interface/Library/Settings/SettingsLocalizable.xcstrings"
);

function fail(message) {
  console.error("Localization validation failed: " + message);
  process.exit(1);
}

function placeholders(value) {
  return [...value.matchAll(/%(?:\d+\$)?(?:@|d|lld|ld|s)/g)]
    .map((match) => match[0].replace(/%\d+\$/, "%"))
    .sort();
}

function localizedValue(entry, language) {
  const localization = entry.localizations?.[language];
  return (
    localization?.stringUnit?.value ??
    localization?.variations?.plural?.other?.stringUnit?.value
  );
}

const mainCatalog = JSON.parse(fs.readFileSync(mainCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(mainCatalog.strings)) {
  const chinese = localizedValue(entry, "zh-Hans");
  if (!chinese) fail("missing zh-Hans translation: " + key);
  const expected = placeholders(key);
  const actual = placeholders(chinese);
  if (expected.join("|") !== actual.join("|")) {
    fail('placeholder mismatch for "' + key + '": ' + expected + " != " + actual);
  }
}

const legacyMainStringsPath = path.join(
  root,
  "browser/Reynard/Resources/zh-Hans.lproj/Localizable.strings"
);
if (fs.existsSync(legacyMainStringsPath)) {
  fail("Localizable.strings conflicts with Localizable.xcstrings in the Reynard target");
}

const addonCatalog = JSON.parse(fs.readFileSync(addonCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(addonCatalog.strings)) {
  const english = entry.localizations?.en?.stringUnit?.value ?? key;
  const chinese = localizedValue(entry, "zh-Hans");
  if (!chinese) fail("missing add-on zh-Hans translation: " + key);
  if (placeholders(english).join("|") !== placeholders(chinese).join("|")) {
    fail('add-on placeholder mismatch for "' + key + '"');
  }
}

const settingsCatalog = JSON.parse(fs.readFileSync(settingsCatalogPath, "utf8"));
for (const [key, entry] of Object.entries(settingsCatalog.strings)) {
  const english = localizedValue(entry, "en") ?? key;
  const chinese = localizedValue(entry, "zh-Hans");
  if (!chinese) fail("missing settings zh-Hans translation: " + key);
  if (placeholders(english).join("|") !== placeholders(chinese).join("|")) {
    fail('settings placeholder mismatch for "' + key + '"');
  }
}

// Validate source keys too: a catalog-only check misses new, untranslated UI text.
const catalogs = {
  Localizable: mainCatalog,
  AddonLocalizable: addonCatalog,
  SettingsLocalizable: settingsCatalog,
};
function validateSourceKeys(directory) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const filePath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      validateSourceKeys(filePath);
    } else if (entry.name.endsWith(".swift")) {
      const source = fs.readFileSync(filePath, "utf8");
      const calls = /NSLocalizedString\(\s*("(?:[^"\\]|\\.)*")\s*,\s*(?:tableName:\s*"([^"]+)"\s*,)?/g;
      for (const match of source.matchAll(calls)) {
        if (match[1].includes("\\(")) {
          fail(`interpolated localization key in ${path.relative(root, filePath)}; use a format placeholder`);
        }
        const jsonLiteral = match[1].replace(/(?<!\\)\\u\{([0-9a-fA-F]+)\}/g, (_, hex) =>
          JSON.stringify(String.fromCodePoint(parseInt(hex, 16))).slice(1, -1)
        );
        const key = JSON.parse(jsonLiteral);
        const table = match[2] ?? "Localizable";
        if (catalogs[table] && !Object.hasOwn(catalogs[table].strings, key)) {
          fail(`missing source key ${JSON.stringify(key)} in ${table} (${path.relative(root, filePath)})`);
        }
      }
    }
  }
}
validateSourceKeys(path.join(root, "browser/Reynard"));

const projectFile = fs.readFileSync(
  path.join(root, "browser/Reynard.xcodeproj/project.pbxproj"),
  "utf8"
);
if (!projectFile.includes('"zh-Hans"')) fail("Xcode project does not declare zh-Hans");

console.log(
  "Localization validation passed: " +
    Object.keys(mainCatalog.strings).length +
    " app strings and " +
    Object.keys(addonCatalog.strings).length +
    " add-on strings and " + Object.keys(settingsCatalog.strings).length + " settings strings"
);
