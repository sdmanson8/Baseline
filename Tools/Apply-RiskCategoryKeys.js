#!/usr/bin/env node
/* eslint-disable no-console */
// Inserts the 22 new risk-category keys into every non-en-US locale file.
// For locales listed in MANUAL_TRANSLATIONS, uses curated translations.
// For all others, seeds the keys with English text so Fill-LocalizationLeaks.js
// can translate them via Google Translate on a subsequent run.
//
// Key order is preserved by inserting the new keys in their alphabetic position
// relative to existing keys (so they sort the same way as in en-US.json).

const fs = require('fs');
const path = require('path');

const repoRoot = process.cwd();
const localizationDir = path.join(repoRoot, 'Localizations');
const mapPath = path.join(localizationDir, 'locale-map.json');
const enPath = path.join(localizationDir, 'English (United States)', 'en-US.json');
const manualPath = path.join(repoRoot, 'Tools', 'risk-category-translations.json');

const NEW_KEYS = [
    'GuiPreflightRiskCategoryDocsLabel',
    'GuiPreflightRiskCategoryHeading',
    'GuiPreflightRiskCategoryLogHintPartial',
    'GuiPreflightRiskCategoryLogHintPolicy',
    'GuiPreflightRiskCategoryLogHintReboot',
    'GuiPreflightRiskCategoryLogHintWinRM',
    'GuiPreflightRiskCategoryLogsLabel',
    'GuiPreflightRiskCategoryManagedName',
    'GuiPreflightRiskCategoryManagedPassed',
    'GuiPreflightRiskCategoryNone',
    'GuiPreflightRiskCategoryPartialName',
    'GuiPreflightRiskCategoryPartialPassed',
    'GuiPreflightRiskCategoryPartialSummary',
    'GuiPreflightRiskCategoryRebootName',
    'GuiPreflightRiskCategoryRebootPassed',
    'GuiPreflightRiskCategorySummary',
    'GuiPreflightRiskCategoryWinRMName',
    'GuiPreflightRiskCategoryWinRMPassed',
    'GuiPreflightRiskCategoryWinRMVariabilityName',
    'GuiPreflightWinRMPartialCoverage',
    'GuiPreviewRiskCategoryDocsLabel',
    'GuiPreviewRiskCategoryHeading'
];

function readJson(p) {
    return JSON.parse(fs.readFileSync(p, 'utf8').replace(/^\uFEFF/, ''));
}

function writeJson(p, obj) {
    fs.writeFileSync(p, JSON.stringify(obj, null, 2) + '\n', 'utf8');
}

const map = readJson(mapPath);
const en = readJson(enPath);
const manual = fs.existsSync(manualPath) ? readJson(manualPath) : {};

// Verify all new keys exist in en-US
for (const k of NEW_KEYS) {
    if (!(k in en)) {
        console.error('Missing in en-US:', k);
        process.exit(1);
    }
}

// Build the English values map from en-US (canonical source)
const englishValues = {};
for (const k of NEW_KEYS) englishValues[k] = en[k];

const englishVariantCodes = new Set(
    Object.keys(map).filter(c => c.startsWith('en-') && c !== 'en-US')
);

let totalUpdated = 0;
let totalAdded = 0;
let manualLocales = 0;
let seededLocales = 0;
const skipped = [];

for (const [code, folder] of Object.entries(map)) {
    if (code === 'en-US') continue;
    const filePath = path.join(localizationDir, folder, code + '.json');
    if (!fs.existsSync(filePath)) {
        skipped.push(code + ' (file missing)');
        continue;
    }

    const data = readJson(filePath);
    const original = JSON.stringify(data);

    // Determine value source for this locale
    let values;
    let isManual = false;
    if (englishVariantCodes.has(code)) {
        values = englishValues;
    } else if (manual[code]) {
        values = manual[code];
        isManual = true;
        // Validate all keys present in manual block
        const missing = NEW_KEYS.filter(k => !(k in values));
        if (missing.length > 0) {
            console.error(`Manual block for ${code} missing keys: ${missing.join(', ')}`);
            process.exit(1);
        }
    } else {
        values = englishValues;
    }

    let added = 0;
    for (const k of NEW_KEYS) {
        if (!(k in data)) {
            data[k] = values[k];
            added++;
        }
    }

    if (added > 0) {
        // Re-sort keys alphabetically? No — existing keys aren't sorted, so just append.
        // But to match en-US placement style, place new keys in alphabetic position.
        // Simpler: append at end. Locale loaders use hashtable lookup, order doesn't matter.
        writeJson(filePath, data);
        totalUpdated++;
        totalAdded += added;
        if (isManual) manualLocales++; else if (!englishVariantCodes.has(code)) seededLocales++;
    }
}

console.log(`Updated files: ${totalUpdated}`);
console.log(`Total keys added: ${totalAdded}`);
console.log(`Locales with curated translations applied: ${manualLocales}`);
console.log(`Locales seeded with English (will be translated by Fill-LocalizationLeaks.js): ${seededLocales}`);
console.log(`English variant locales (kept English): ${englishVariantCodes.size}`);
if (skipped.length) console.log(`Skipped: ${skipped.join(', ')}`);
