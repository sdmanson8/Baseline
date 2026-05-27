#!/usr/bin/env node
/* eslint-disable no-console */
const fs = require('fs');
const path = require('path');
const { execFileSync } = require('child_process');

const repoRoot = process.cwd();
const localizationDir = process.env.LOCALIZATION_ROOT
    ? path.resolve(process.env.LOCALIZATION_ROOT)
    : path.join(repoRoot, 'Localizations');
const qaPath = path.join(repoRoot, 'Tools/Test-LocalizationQA.ps1');
const sourceFile = process.env.LOCALIZATION_SOURCE_FILE || 'en-US.json';
const localeFilePattern = /^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\.json$/;
const targetLocales = new Set(
    (process.env.LOCALIZATION_TARGETS || '')
        .split(',')
        .map((locale) => locale.trim())
        .filter(Boolean),
);
const unfinishedLocales = new Set(
    (process.env.LOCALIZATION_UNFINISHED_LOCALES || '')
        .split(',')
        .map((locale) => locale.trim())
        .filter(Boolean),
);
const lockedEnglishKeysPath = path.join(localizationDir, 'english_locked_keys.json');
const lockedEnglishKeys = fs.existsSync(lockedEnglishKeysPath)
    ? readJsonFile(lockedEnglishKeysPath)
    : [];

const qa = fs.readFileSync(qaPath, 'utf8');

function readJsonFile(filePath)
{
    return JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
}

function walkJsonFiles(rootDir)
{
    const files = [];
    const stack = [rootDir];

    while (stack.length > 0)
    {
        const current = stack.pop();
        for (const entry of fs.readdirSync(current, { withFileTypes: true }))
        {
            const fullPath = path.join(current, entry.name);
            if (entry.isDirectory())
            {
                stack.push(fullPath);
            }
            else if (entry.isFile() && entry.name.endsWith('.json'))
            {
                files.push(fullPath);
            }
        }
    }

    return files;
}

function findJsonFile(rootDir, fileName)
{
    const matches = walkJsonFiles(rootDir).filter((filePath) => path.basename(filePath) === fileName);
    if (matches.length === 0)
    {
        throw new Error(`Missing locale file: ${fileName}`);
    }

    if (matches.length > 1)
    {
        throw new Error(`Multiple locale files named ${fileName} found under ${rootDir}`);
    }

    return matches[0];
}

const enPath = findJsonFile(localizationDir, sourceFile);
const en = readJsonFile(enPath);

function parseStringArray(source, name)
{
    const match = source.match(new RegExp(String.raw`\$${name} = @\(([\s\S]*?)\)`, 'm'));
    if (!match)
    {
        throw new Error(`Could not parse ${name} from ${qaPath}`);
    }

    return [...match[1].matchAll(/'([^']+)'/g)].map((m) => m[1]);
}

const exemptKeys = new Set([
    ...parseStringArray(qa, 'ExemptKeys'),
    ...lockedEnglishKeys,
]);
const englishVariantLocales = new Set(
    walkJsonFiles(localizationDir)
        .map((filePath) => path.basename(filePath))
        .filter((file) => localeFilePattern.test(file))
        .filter((file) => file.startsWith('en-'))
        .filter((file) => file !== sourceFile)
);

const localeFiles = walkJsonFiles(localizationDir)
    .filter((filePath) => localeFilePattern.test(path.basename(filePath)))
    .map((filePath) => ({
        filePath,
        fileName: path.basename(filePath),
    }))
    .filter(({ fileName }) => fileName !== sourceFile)
    .filter(({ fileName }) => !englishVariantLocales.has(fileName))
    .filter(({ fileName }) => !unfinishedLocales.has(fileName))
    .sort((left, right) => left.fileName.localeCompare(right.fileName))
    .filter(({ fileName }) => targetLocales.size === 0 || targetLocales.has(fileName));

const batchSize = Number.parseInt(process.env.LOCALIZATION_BATCH_SIZE || '12', 10);
const concurrency = Number.parseInt(process.env.LOCALIZATION_CONCURRENCY || '4', 10);
const languageSupportCache = new Map();

function translateUrl(lang, text)
{
    const params = new URLSearchParams({
        client: 'gtx',
        sl: 'en',
        tl: lang,
        dt: 't',
        q: text,
    });

    return `https://translate.googleapis.com/translate_a/single?${params.toString()}`;
}

async function sleep(ms)
{
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function fetchJson(url)
{
    const output = execFileSync('curl', ['-L', '--fail', '--silent', '--show-error', url], {
        encoding: 'utf8',
    });

    return JSON.parse(output);
}

async function translateOne(lang, text)
{
    let data;
    try
    {
        data = fetchJson(translateUrl(lang, text));
    }
    catch (error)
    {
        throw new Error(`Translate request failed for ${lang}: ${text.slice(0, 80)} (${error.message})`);
    }

    if (!Array.isArray(data) || !Array.isArray(data[0]))
    {
        throw new Error(`Unexpected translation payload for ${lang}: ${text.slice(0, 80)}`);
    }

    return data[0].map((segment) => segment[0]).join('');
}

async function supportsLanguage(lang)
{
    if (languageSupportCache.has(lang))
    {
        return languageSupportCache.get(lang);
    }

    try
    {
        await translateOne(lang, 'Hello');
        languageSupportCache.set(lang, true);
        return true;
    }
    catch (error)
    {
        const message = String(error.message);
        if (message.includes('(400)') || /\b400\b/.test(message))
        {
            languageSupportCache.set(lang, false);
            return false;
        }

        console.warn(`[WARN] ${lang}: language probe failed (${error.message}); leaving this locale untranslated for this run.`);
        languageSupportCache.set(lang, false);
        return false;
    }
}

async function translateBatch(lang, texts)
{
    if (texts.length === 0)
    {
        return [];
    }

    if (texts.length === 1)
    {
        return [await translateOne(lang, texts[0])];
    }

    const payload = texts.join('\n');
    let data;
    try
    {
        data = fetchJson(translateUrl(lang, payload));
    }
    catch (error)
    {
        if (texts.length > 1)
        {
            const midpoint = Math.floor(texts.length / 2);
            const left = await translateBatch(lang, texts.slice(0, midpoint));
            const right = await translateBatch(lang, texts.slice(midpoint));
            return left.concat(right);
        }

        throw new Error(`Translate batch failed for ${lang} with ${texts.length} item(s) (${error.message})`);
    }

    const segments = Array.isArray(data) ? data[0] : null;
    if (!Array.isArray(segments) || segments.length !== texts.length)
    {
        const midpoint = Math.floor(texts.length / 2);
        const left = await translateBatch(lang, texts.slice(0, midpoint));
        const right = await translateBatch(lang, texts.slice(midpoint));
        return left.concat(right);
    }

    return segments.map((segment) => String(segment[0]).replace(/\n$/, ''));
}

async function translateFile(localeEntry)
{
    const filePath = typeof localeEntry === 'string' ? localeEntry : localeEntry.filePath;
    const fileName = path.basename(filePath);
    const locale = readJsonFile(filePath);
    const lang = fileName.replace(/\.json$/, '');

    const targetKeys = Object.keys(en).filter((key) =>
        !exemptKeys.has(key) &&
        (!Object.prototype.hasOwnProperty.call(locale, key) ||
            typeof locale[key] !== 'string' ||
            locale[key].trim() === '' ||
            locale[key] === en[key])
    );
    if (targetKeys.length === 0)
    {
        console.log(`[SKIP] ${fileName} already has no exact-English leakage`);
        return { fileName, translated: 0, remaining: 0 };
    }

    if (!(await supportsLanguage(lang)))
    {
        console.log(`[SKIP] ${fileName} is not supported by translate.googleapis.com; leaving ${targetKeys.length} exact-English leak(s) unchanged`);
        return { fileName, translated: 0, remaining: targetKeys.length };
    }

    try
    {
        const bySource = new Map();
        for (const key of targetKeys)
        {
            const source = en[key];
            if (!bySource.has(source))
            {
                bySource.set(source, []);
            }

            bySource.get(source).push(key);
        }

        const sources = [...bySource.keys()];
        const translatedSources = new Map();
        let translatedCount = 0;

        const singleLineSources = [];
        const multiLineSources = [];
        for (const source of sources)
        {
            if (source.includes('\n'))
            {
                multiLineSources.push(source);
            }
            else
            {
                singleLineSources.push(source);
            }
        }

        console.log(`[START] ${fileName}: ${targetKeys.length} exact-English leak(s), ${sources.length} unique string(s)`);

        for (let i = 0; i < singleLineSources.length; i += batchSize)
        {
            const batch = singleLineSources.slice(i, i + batchSize);
            const translated = await translateBatch(lang, batch);
            for (let j = 0; j < batch.length; j += 1)
            {
                translatedSources.set(batch[j], translated[j]);
            }

            translatedCount += batch.length;
            console.log(`[${fileName}] ${Math.min(i + batch.length, singleLineSources.length)}/${singleLineSources.length} single-line source(s) translated`);

            await sleep(50);
        }

        for (const source of multiLineSources)
        {
            translatedSources.set(source, await translateOne(lang, source));
            translatedCount += 1;
        }

        for (const [source, keys] of bySource.entries())
        {
            const translated = translatedSources.get(source);
            for (const key of keys)
            {
                locale[key] = translated;
            }
        }

        fs.writeFileSync(filePath, `${JSON.stringify(locale, null, 2)}\n`, 'utf8');

        const remaining = Object.keys(en).filter((key) =>
            !exemptKeys.has(key) &&
            (!Object.prototype.hasOwnProperty.call(locale, key) ||
                typeof locale[key] !== 'string' ||
                locale[key].trim() === '' ||
                locale[key] === en[key])
        );
        console.log(`[DONE] ${fileName}: translated ${translatedCount} source string(s), remaining exact-English leaks=${remaining.length}`);

        return { fileName, translated: translatedCount, remaining: remaining.length };
    }
    catch (error)
    {
        console.warn(`[WARN] ${fileName}: translation failed (${error.message}); leaving locale untranslated for this run.`);
        return { fileName, translated: 0, remaining: targetKeys.length };
    }
}

async function main()
{
    console.log(`Locale files to inspect: ${localeFiles.length}`);
    console.log(`Batch size: ${batchSize}, concurrency: ${concurrency}`);

    const pending = [...localeFiles];
    const results = [];

    async function worker(workerId)
    {
        while (pending.length > 0)
        {
            const localeEntry = pending.shift();
            if (!localeEntry)
            {
                return;
            }

            try
            {
                const result = await translateFile(localeEntry);
                results.push(result);
            }
            catch (error)
            {
                console.error(`[FAIL] ${localeEntry.fileName}: ${error.message}`);
                throw error;
            }
        }
    }

    await Promise.all(Array.from({ length: concurrency }, (_, workerId) => worker(workerId)));

    const remainingTotal = results.reduce((sum, result) => sum + result.remaining, 0);
    console.log(`All done. Remaining exact-English leaks across processed files: ${remainingTotal}`);
    if (/^(1|true|yes|on)$/i.test(String(process.env.LOCALIZATION_FAIL_ON_REMAINING || '')) && remainingTotal > 0)
    {
        throw new Error(`Localization generation left ${remainingTotal} untranslated or blank value(s).`);
    }
}

main().catch((error) =>
{
    console.error(error);
    process.exit(1);
});
