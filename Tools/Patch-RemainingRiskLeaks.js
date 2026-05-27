#!/usr/bin/env node
/* eslint-disable no-console */
// Patches the residual exact-English leaks in the 22 risk-category keys that
// Fill-LocalizationLeaks.js could not handle:
//   - Single "Logs" word in af, ga, ha, is, wo (Google echoed it back)
//   - Full key sets in nn (Norwegian Nynorsk), prs (Dari), quc (K'iche')
//     — unsupported by translate.googleapis.com.

const fs = require('fs');
const path = require('path');

const localizationDir = path.join(process.cwd(), 'Localizations');

const PATCHES = {
    'Afrikaans/af.json': {
        'GuiPreflightRiskCategoryLogsLabel': 'Loglêers'
    },
    'Irish/ga.json': {
        'GuiPreflightRiskCategoryLogsLabel': 'Logaí'
    },
    'Hausa/ha.json': {
        'GuiPreflightRiskCategoryLogsLabel': 'Bayanan log'
    },
    'Icelandic/is.json': {
        'GuiPreflightRiskCategoryLogsLabel': 'Atburðaskrár'
    },
    'Wolof/wo.json': {
        'GuiPreflightRiskCategoryLogsLabel': 'Tëralinu log'
    },
    'Norwegian Nynorsk/nn.json': {
        'GuiPreflightRiskCategoryDocsLabel': 'Utbetringsrettleiing',
        'GuiPreflightRiskCategoryHeading': 'Risikokategoriar:',
        'GuiPreflightRiskCategoryLogHintPartial': 'Bruk RunId {0} i orkestreringshistorikken for å finne dei mislukka delsteg.',
        'GuiPreflightRiskCategoryLogHintPolicy': 'Sjå gjennom oppføringar for administrerte retningslinjer i støttepakken (PolicyConflictSignals).',
        'GuiPreflightRiskCategoryLogHintReboot': 'Årsaker til ventande omstart vert registrerte under PreflightChecks i loggen.',
        'GuiPreflightRiskCategoryLogHintWinRM': 'Sjå WinRM-detaljlinjer i fjernkonsoll-loggen og i utskriftene for støttepakken.',
        'GuiPreflightRiskCategoryLogsLabel': 'Loggar',
        'GuiPreflightRiskCategoryManagedName': 'Administrert sluttpunktsretningslinje',
        'GuiPreflightRiskCategoryManagedPassed': 'Ingen konfliktar med administrerte sluttpunkt vart oppdaga.',
        'GuiPreflightRiskCategoryNone': 'Ingen signal om retningslinjekonflikt vart oppdaga.',
        'GuiPreflightRiskCategoryPartialName': 'Risiko for delvis vellukka utrulling',
        'GuiPreflightRiskCategoryPartialPassed': 'Ingen delvis vellukka utrullingar registrerte dei siste 7 dagane.',
        'GuiPreflightRiskCategoryPartialSummary': '{0} nylege utrullingar enda med delvis suksess (nyaste: {1}, køyring {2}).',
        'GuiPreflightRiskCategoryRebootName': 'Ventande omstart',
        'GuiPreflightRiskCategoryRebootPassed': 'Ingen ventande omstart vart oppdaga.',
        'GuiPreflightRiskCategorySummary': 'Merka risikokategoriar: {0}.',
        'GuiPreflightRiskCategoryWinRMName': 'WinRM-tilgjenge',
        'GuiPreflightRiskCategoryWinRMPassed': 'Alle mål er tilgjengelege via WinRM.',
        'GuiPreflightRiskCategoryWinRMVariabilityName': 'Variasjon i WinRM-tilgjenge',
        'GuiPreflightWinRMPartialCoverage': 'Delvis WinRM-dekning: {0} av {1} mål er tilgjengelege. Ikkje tilgjengelege: {2}',
        'GuiPreviewRiskCategoryDocsLabel': 'Utbetringsrettleiing',
        'GuiPreviewRiskCategoryHeading': 'Risikomedvitne kontrollar merkte før denne køyringa:'
    },
    'Dari/prs.json': {
        'GuiPreflightRiskCategoryDocsLabel': 'رهنمای رفع مشکل',
        'GuiPreflightRiskCategoryHeading': 'دسته‌های ریسک:',
        'GuiPreflightRiskCategoryLogHintPartial': 'برای یافتن زیرمراحل ناکام، از RunId {0} در تاریخچه ارکستریشن استفاده کنید.',
        'GuiPreflightRiskCategoryLogHintPolicy': 'ورودی‌های پالیسی مدیریت‌شده را در بسته پشتیبانی (PolicyConflictSignals) مرور کنید.',
        'GuiPreflightRiskCategoryLogHintReboot': 'دلایل راه‌اندازی مجدد در انتظار، در PreflightChecks در ثبت ضبط می‌شوند.',
        'GuiPreflightRiskCategoryLogHintWinRM': 'سطرهای جزئیات WinRM را در ثبت کنسول ریموت و رونوشت‌های بسته پشتیبانی ببینید.',
        'GuiPreflightRiskCategoryLogsLabel': 'ثبت‌ها',
        'GuiPreflightRiskCategoryManagedName': 'پالیسی نقطه پایانی مدیریت‌شده',
        'GuiPreflightRiskCategoryManagedPassed': 'هیچ تضاد نقطه پایانی مدیریت‌شده‌ای شناسایی نشد.',
        'GuiPreflightRiskCategoryNone': 'هیچ سیگنال تضاد پالیسی شناسایی نشد.',
        'GuiPreflightRiskCategoryPartialName': 'ریسک استقرار با موفقیت جزئی',
        'GuiPreflightRiskCategoryPartialPassed': 'در ۷ روز گذشته هیچ استقرار با موفقیت جزئی ثبت نشده است.',
        'GuiPreflightRiskCategoryPartialSummary': '{0} استقرار اخیر با موفقیت جزئی پایان یافت (جدیدترین: {1}، اجرای {2}).',
        'GuiPreflightRiskCategoryRebootName': 'راه‌اندازی مجدد در انتظار',
        'GuiPreflightRiskCategoryRebootPassed': 'هیچ راه‌اندازی مجدد در انتظاری شناسایی نشد.',
        'GuiPreflightRiskCategorySummary': 'دسته‌های ریسک علامت‌گذاری شده: {0}.',
        'GuiPreflightRiskCategoryWinRMName': 'دسترسی WinRM',
        'GuiPreflightRiskCategoryWinRMPassed': 'تمام اهداف از طریق WinRM در دسترس هستند.',
        'GuiPreflightRiskCategoryWinRMVariabilityName': 'تغییرپذیری دسترسی WinRM',
        'GuiPreflightWinRMPartialCoverage': 'پوشش جزئی WinRM: {0} از {1} هدف در دسترس. غیرقابل دسترس: {2}',
        'GuiPreviewRiskCategoryDocsLabel': 'رهنمای رفع مشکل',
        'GuiPreviewRiskCategoryHeading': 'بررسی‌های آگاه از ریسک که قبل از این اجرا علامت‌گذاری شدند:'
    },
    'Kʼicheʼ/quc.json': {
        'GuiPreflightRiskCategoryDocsLabel': 'Kʼutbʼal rech kʼaxkʼolil',
        'GuiPreflightRiskCategoryHeading': 'Cholaj rech kʼaxkʼolil:',
        'GuiPreflightRiskCategoryLogHintPartial': 'Chakojoʼ ri RunId {0} pa ri loqʼolaj rech ri orquestración rech kariqitaj ri xebʼanataj.',
        'GuiPreflightRiskCategoryLogHintPolicy': 'Chawila ri taqanik rech ri taqanem (PolicyConflictSignals) pa ri tobʼanik chʼaqap.',
        'GuiPreflightRiskCategoryLogHintReboot': 'Ri rumal rech ri kʼastajibʼal kayoqotaj pa PreflightChecks pa ri tzʼibʼanik.',
        'GuiPreflightRiskCategoryLogHintWinRM': 'Chawila ri taqanik rech WinRM pa ri tzʼibʼanik rech ri naj kʼolibʼal xuqujeʼ pa ri tzijonik rech ri tobʼanik chʼaqap.',
        'GuiPreflightRiskCategoryLogsLabel': 'Tzʼibʼanik',
        'GuiPreflightRiskCategoryManagedName': 'Taqanem rech kʼolibʼal kʼamatal',
        'GuiPreflightRiskCategoryManagedPassed': 'Maj jun chʼoʼj rech kʼolibʼal kʼamatal xkʼulmataj.',
        'GuiPreflightRiskCategoryNone': 'Maj retalil rech chʼoʼj taqanem xkʼulmataj.',
        'GuiPreflightRiskCategoryPartialName': 'Kʼaxkʼolil rech jastaq kabʼan',
        'GuiPreflightRiskCategoryPartialPassed': 'Maj jastaq kabʼan xtzʼibʼax pa ri 7 qʼij.',
        'GuiPreflightRiskCategoryPartialSummary': '{0} kʼakʼ taq jastaq xeqʼax pa jastaq (nabʼe: {1}, bʼanik {2}).',
        'GuiPreflightRiskCategoryRebootName': 'Kʼastajibʼal kayoqotaj',
        'GuiPreflightRiskCategoryRebootPassed': 'Maj kʼastajibʼal kayoqotaj xkʼulmataj.',
        'GuiPreflightRiskCategorySummary': 'Cholaj rech kʼaxkʼolil retalil: {0}.',
        'GuiPreflightRiskCategoryWinRMName': 'Riqonem rech WinRM',
        'GuiPreflightRiskCategoryWinRMPassed': 'Konojel ri kʼolibʼal kariqitaj rumal WinRM.',
        'GuiPreflightRiskCategoryWinRMVariabilityName': 'Kʼexonik rech riqonem WinRM',
        'GuiPreflightWinRMPartialCoverage': 'Jastaq chʼukulik WinRM: {0} chi {1} kʼolibʼal kariqitaj. Maj kariqitaj: {2}',
        'GuiPreviewRiskCategoryDocsLabel': 'Kʼutbʼal rech kʼaxkʼolil',
        'GuiPreviewRiskCategoryHeading': 'Ri nikʼoxik rech kʼaxkʼolil retalil rech kʼo kʼi xeʼanjaʼ:'
    }
};

let totalUpdated = 0;
let totalKeys = 0;
for (const [relPath, patches] of Object.entries(PATCHES)) {
    const filePath = path.join(localizationDir, relPath);
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8').replace(/^\uFEFF/, ''));
    let changed = 0;
    for (const [k, v] of Object.entries(patches)) {
        if (data[k] !== v) { data[k] = v; changed++; }
    }
    if (changed > 0) {
        fs.writeFileSync(filePath, JSON.stringify(data, null, 2) + '\n', 'utf8');
        console.log(`[PATCH] ${relPath}: ${changed} key(s) updated`);
        totalUpdated++;
        totalKeys += changed;
    }
}
console.log(`Done. Files patched: ${totalUpdated}, keys patched: ${totalKeys}`);
