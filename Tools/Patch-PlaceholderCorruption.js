#!/usr/bin/env node
/* eslint-disable no-console */
// Repairs placeholder corruption introduced by Google Translate where {0}/{1}/{2}
// got mangled (typically `{0 Use` instead of `{0}`, or 3-arg patterns lost).

const fs = require('fs');
const path = require('path');

const PATCHES = {
    'Odia/or.json': {
        'GuiPreflightRiskCategoryLogHintPartial': 'ବିଫଳ ଉପ-ପଦକ୍ଷେପଗୁଡ଼ିକୁ ଖୋଜିବା ପାଇଁ ଅର୍କେଷ୍ଟ୍ରେସନ୍ ଇତିହାସରେ RunId {0} ବ୍ୟବହାର କରନ୍ତୁ।'
    },
    'Kinyarwanda/rw.json': {
        'GuiPreflightRiskCategoryPartialSummary': '{0} amashyirwaho aheruka yararangiye n\u2019intsinzi y\u2019igice (giheruka: {1}, gukoresha {2}).'
    },
    'Turkmen/tk.json': {
        'GuiPreflightRiskCategoryLogHintPartial': 'Şowsuz kiçi ädimleri tapmak üçin orkestr taryhynda RunId {0} ulanyň.',
        'GuiPreflightRiskCategoryPartialSummary': '{0} soňky ýaýradyşlar bölekleýin üstünlik bilen tamamlandy (iň soňky: {1}, işleýiş {2}).'
    },
    'Tatar/tt.json': {
        'GuiPreflightRiskCategoryLogHintPartial': 'Уңышсыз адымнарны табу өчен оркестр тарихында RunId {0} кулланыгыз.',
        'GuiPreflightRiskCategoryPartialSummary': '{0} күптән түгел чыгарылыш өлешчә уңыш белән тәмамланды (соңгысы: {1}, эш {2}).'
    },
    'Uyghur/ug.json': {
        'GuiPreflightRiskCategoryLogHintPartial': 'مەغلۇپ بولغان تارماق باسقۇچلارنى تېپىش ئۈچۈن ئوركېستىر تارىخىدا RunId {0} نى ئىشلىتىڭ.'
    }
};

let totalKeys = 0;
for (const [relPath, patches] of Object.entries(PATCHES)) {
    const filePath = path.join(process.cwd(), 'Localizations', relPath);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
    let changed = 0;
    for (const [k, v] of Object.entries(patches)) {
        if (data[k] !== v) { data[k] = v; changed++; }
    }
    if (changed > 0) {
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
        console.log(`[PATCH] ${relPath}: ${changed} key(s)`);
        totalKeys += changed;
    }
}
console.log(`Total keys patched: ${totalKeys}`);
