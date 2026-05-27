#!/usr/bin/env bash
set -euo pipefail
shopt -s nullglob

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
localization_dir="$repo_root/Localizations"
qa_path="$repo_root/Tools/Test-LocalizationQA.ps1"
source_file="en-US.json"
locale_file_pattern='^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\.json$'
batch_size="${LOCALIZATION_BATCH_SIZE:-12}"
translate_host_ip="${TRANSLATE_HOST_IP:-}"
scan_mode="${LOCALIZATION_SCANNING_MODE:-exact}"
scan_label="exact-English leak(s)"
target_locales_csv="${LOCALIZATION_TARGETS:-}"
if [[ "$scan_mode" == "terms" ]]; then
    scan_label="term leak(s)"
fi
if [[ -n "$target_locales_csv" ]]; then
    target_locales_csv=",${target_locales_csv//[[:space:]]/},"
fi

find_locale_file() {
    local file_name="$1"
    local -a matches=()
    while IFS= read -r -d '' match; do
        matches+=("$match")
    done < <(find "$localization_dir" -type f -name "$file_name" -print0)

    case "${#matches[@]}" in
        0)
            echo "Missing locale file: $file_name" >&2
            return 1
            ;;
        1)
            printf '%s\n' "${matches[0]}"
            ;;
        *)
            echo "Multiple locale files named $file_name found under $localization_dir" >&2
            return 1
            ;;
    esac
}

en_path="$(find_locale_file "$source_file")"

tmp_root="${TMPDIR:-/tmp}/baseline-localization-leaks"
rm -rf "$tmp_root"
mkdir -p "$tmp_root"

cleanup() {
    rm -rf "$tmp_root"
}
trap cleanup EXIT

translate_curl() {
    local -a args=()
    if [[ -n "$translate_host_ip" ]]; then
        args+=(--resolve "translate.googleapis.com:443:${translate_host_ip}")
    fi

    if [[ "${#args[@]}" -gt 0 ]]; then
        curl "${args[@]}" "$@"
    else
        curl "$@"
    fi
}

count_lines() {
    local file="$1"
    if [[ ! -s "$file" ]]; then
        echo 0
        return
    fi

    wc -l < "$file" | tr -d '[:space:]'
}

generate_targets() {
    local locale_file="$1"
    local single_out="$2"
    local multi_out="$3"

python3 - "$en_path" "$qa_path" "$locale_file" "$single_out" "$multi_out" "$scan_mode" <<'PY'
import json
import pathlib
import re
import sys
import os

en_path, qa_path, locale_path, single_out, multi_out = sys.argv[1:6]
scan_mode = sys.argv[6]
qa = pathlib.Path(qa_path).read_text(encoding='utf-8-sig')
source_file = pathlib.Path(en_path).name
locale_pattern = re.compile(r'^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*\.json$')
localization_root = pathlib.Path(en_path).parent.parent


def parse_string_array(name: str) -> set[str]:
    match = re.search(rf"\${name} = @\(([\s\S]*?)\)", qa)
    if not match:
        raise SystemExit(f"Could not parse {name} from {qa_path}")
    return set(re.findall(r"'([^']+)'", match.group(1)))


exempt_keys = parse_string_array('ExemptKeys')
locked_english_keys_path = pathlib.Path(localization_root) / 'english_locked_keys.json'
if locked_english_keys_path.is_file():
    exempt_keys.update(
        json.loads(locked_english_keys_path.read_text(encoding='utf-8'))
    )
locale_name = pathlib.Path(locale_path).name
if not locale_pattern.match(locale_name):
    pathlib.Path(single_out).write_text('', encoding='utf-8')
    pathlib.Path(multi_out).write_text('', encoding='utf-8')
    sys.exit(0)

english_variant_locales = {
    path.name for path in localization_root.rglob('en-*.json')
    if path.name != source_file
}

if locale_name == source_file or locale_name in english_variant_locales:
    pathlib.Path(single_out).write_text('', encoding='utf-8')
    pathlib.Path(multi_out).write_text('', encoding='utf-8')
    sys.exit(0)

with open(en_path, encoding='utf-8-sig') as handle:
    en = json.load(handle)

with open(locale_path, encoding='utf-8-sig') as handle:
    locale = json.load(handle)

by_source = {}

term_tokens = [token.strip() for token in os.environ.get('LOCALIZATION_TERMS', 'Tweaks,Game Mode').split(',') if token.strip()]
term_tokens_lower = [token.lower() for token in term_tokens]

for key, source in en.items():
    value = locale.get(key)

    if key in exempt_keys:
        continue

    if scan_mode == 'terms':
        if not isinstance(value, str):
            continue
        if not any(token in value.lower() for token in term_tokens_lower):
            continue
    else:
        if value != source:
            continue

    by_source.setdefault(source, []).append(key)

single = []
multi = []
for source, keys in by_source.items():
    entry = {'source': source, 'keys': keys}
    if '\n' in source:
        multi.append(entry)
    else:
        single.append(entry)

with open(single_out, 'w', encoding='utf-8') as handle:
    for entry in single:
        handle.write(json.dumps(entry, ensure_ascii=False) + '\n')

with open(multi_out, 'w', encoding='utf-8') as handle:
    for entry in multi:
        handle.write(json.dumps(entry, ensure_ascii=False) + '\n')
PY
}

supports_language() {
    local lang="$1"
    local probe_file
    probe_file="$(mktemp "$tmp_root/probe.XXXXXX")"
    local probe_status=0
    set +e
    translate_curl -G -L --fail --silent --show-error \
        --retry 3 --retry-all-errors --retry-delay 1 \
        --data-urlencode client=gtx \
        --data-urlencode sl=en \
        --data-urlencode tl="$lang" \
        --data-urlencode dt=t \
        --data-urlencode q=Hello \
        'https://translate.googleapis.com/translate_a/single' \
        > "$probe_file"
    probe_status=$?
    set -e
    if [[ "$probe_status" -ne 0 ]]; then
        rm -f "$probe_file"
        return 1
    fi

    if ! jq -e 'type == "array" and .[0] and .[0][0] and .[0][0][0]' "$probe_file" >/dev/null; then
        rm -f "$probe_file"
        return 1
    fi

    rm -f "$probe_file"
    return 0
}

translate_jsonl_batch() {
    local lang="$1"
    local batch_jsonl="$2"
    local out_json="$3"

    local count
    count="$(count_lines "$batch_jsonl")"
    if [[ "$count" -eq 0 ]]; then
        printf '[]\n' > "$out_json"
        return 0
    fi

    local sources_file response_file source_count trans_count
    sources_file="$(mktemp "$tmp_root/sources.XXXXXX")"
    response_file="$(mktemp "$tmp_root/response.XXXXXX")"

    jq -r '.source' "$batch_jsonl" > "$sources_file"

    if [[ "$count" -eq 1 ]]; then
        local single_status=0
        set +e
        translate_curl -G -L --fail --silent --show-error \
            --retry 3 --retry-all-errors --retry-delay 1 \
            --data-urlencode client=gtx \
            --data-urlencode sl=en \
            --data-urlencode tl="$lang" \
            --data-urlencode dt=t \
            --data-urlencode "q@$sources_file" \
            'https://translate.googleapis.com/translate_a/single' \
            | jq -c '[.[0] | map(.[0]) | join("")]' > "$response_file"
        single_status=$?
        set -e
        if [[ "$single_status" -eq 0 ]]; then

            if jq -e 'type == "array" and length == 1 and (.[0] | type == "string")' "$response_file" >/dev/null; then
                mv "$response_file" "$out_json"
                rm -f "$sources_file"
                return 0
            fi
        fi
    else
        local batch_status=0
        set +e
        translate_curl -G -L --fail --silent --show-error \
            --retry 3 --retry-all-errors --retry-delay 1 \
            --data-urlencode client=gtx \
            --data-urlencode sl=en \
            --data-urlencode tl="$lang" \
            --data-urlencode dt=t \
            --data-urlencode "q@$sources_file" \
            'https://translate.googleapis.com/translate_a/single' \
            | jq -c '.[0] | map(.[0])' > "$response_file"
        batch_status=$?
        set -e
        if [[ "$batch_status" -eq 0 ]]; then

            if jq -e 'type == "array"' "$response_file" >/dev/null; then
                source_count="$(jq -s 'length' "$batch_jsonl")"
                trans_count="$(jq 'length' "$response_file")"
                if [[ "$source_count" -eq "$trans_count" ]]; then
                    mv "$response_file" "$out_json"
                    rm -f "$sources_file"
                    return 0
                fi
            fi
        fi
    fi

    rm -f "$sources_file" "$response_file"

    if [[ "$count" -eq 1 ]]; then
        return 1
    fi

    local midpoint left_jsonl right_jsonl left_out right_out
    midpoint=$((count / 2))
    if [[ "$midpoint" -lt 1 ]]; then
        midpoint=1
    fi

    left_jsonl="$(mktemp "$tmp_root/left.XXXXXX")"
    right_jsonl="$(mktemp "$tmp_root/right.XXXXXX")"
    sed -n "1,${midpoint}p" "$batch_jsonl" > "$left_jsonl"
    sed -n "$((midpoint + 1)),${count}p" "$batch_jsonl" > "$right_jsonl"

    left_out="$(mktemp "$tmp_root/left-out.XXXXXX")"
    right_out="$(mktemp "$tmp_root/right-out.XXXXXX")"

    if ! translate_jsonl_batch "$lang" "$left_jsonl" "$left_out"; then
        rm -f "$left_jsonl" "$right_jsonl" "$left_out" "$right_out"
        return 1
    fi

    if ! translate_jsonl_batch "$lang" "$right_jsonl" "$right_out"; then
        rm -f "$left_jsonl" "$right_jsonl" "$left_out" "$right_out"
        return 1
    fi

    jq -s 'add' "$left_out" "$right_out" > "$out_json"
    rm -f "$left_jsonl" "$right_jsonl" "$left_out" "$right_out"
    return 0
}

apply_translation_batch() {
    local locale_file="$1"
    local batch_jsonl="$2"
    local translations_json="$3"

    python3 - "$locale_file" "$batch_jsonl" "$translations_json" <<'PY'
import json
import pathlib
import sys

locale_path, batch_path, translations_path = sys.argv[1:]
with open(locale_path, encoding='utf-8') as handle:
    locale = json.load(handle)

rows = []
with open(batch_path, encoding='utf-8') as handle:
    for line in handle:
        line = line.strip()
        if line:
            rows.append(json.loads(line))

with open(translations_path, encoding='utf-8') as handle:
    translations = json.load(handle)

if len(rows) != len(translations):
    raise SystemExit(
        f"Translation count mismatch for {locale_path}: "
        f"{len(rows)} source string(s) vs {len(translations)} translation(s)"
    )

for row, translation in zip(rows, translations):
    for key in row['keys']:
        locale[key] = translation

pathlib.Path(locale_path).write_text(
    json.dumps(locale, ensure_ascii=False, indent=2) + '\n',
    encoding='utf-8',
)
PY
}

process_locale() {
    local locale_file="$1"
    local locale_name
    locale_name="$(basename "$locale_file")"

    local single_targets="$tmp_root/${locale_name}.single.jsonl"
    local multi_targets="$tmp_root/${locale_name}.multi.jsonl"

    generate_targets "$locale_file" "$single_targets" "$multi_targets"

    local single_count multi_count target_count
    single_count="$(count_lines "$single_targets")"
    multi_count="$(count_lines "$multi_targets")"
    target_count=$((single_count + multi_count))

    if [[ "$target_count" -eq 0 ]]; then
        echo "[SKIP] $locale_name already has no $scan_label"
        return 0
    fi

    local lang="${locale_name%.json}"
    if [[ "$scan_mode" != "terms" ]]; then
        if ! supports_language "$lang"; then
            echo "[SKIP] $locale_name is not supported by translate.googleapis.com; leaving $target_count $scan_label unchanged"
            return 0
        fi
    fi

    echo "[START] $locale_name: $target_count $scan_label, $target_count unique string(s)"

    local translated_total=0

    if [[ "$single_count" -gt 0 ]]; then
        local start end batch_jsonl translated_json batch_count
        for ((start = 1; start <= single_count; start += batch_size)); do
            end=$((start + batch_size - 1))
            batch_jsonl="$(mktemp "$tmp_root/${locale_name}.batch.XXXXXX")"
            translated_json="$(mktemp "$tmp_root/${locale_name}.translated.XXXXXX")"
            sed -n "${start},${end}p" "$single_targets" > "$batch_jsonl"

            if ! translate_jsonl_batch "$lang" "$batch_jsonl" "$translated_json"; then
                echo "[FAIL] $locale_name: unable to translate batch starting at line $start"
                rm -f "$batch_jsonl" "$translated_json"
                continue
            fi

            if ! apply_translation_batch "$locale_file" "$batch_jsonl" "$translated_json"; then
                echo "[FAIL] $locale_name: unable to apply translated batch starting at line $start"
                rm -f "$batch_jsonl" "$translated_json"
                continue
            fi

            batch_count="$(count_lines "$batch_jsonl")"
            translated_total=$((translated_total + batch_count))
            echo "[$locale_name] ${translated_total}/${single_count} single-line source(s) translated"
            rm -f "$batch_jsonl" "$translated_json"
        done
    fi

    if [[ "$multi_count" -gt 0 ]]; then
        local line batch_jsonl translated_json
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            batch_jsonl="$(mktemp "$tmp_root/${locale_name}.multi.XXXXXX")"
            translated_json="$(mktemp "$tmp_root/${locale_name}.multi.translated.XXXXXX")"
            printf '%s\n' "$line" > "$batch_jsonl"

            if ! translate_jsonl_batch "$lang" "$batch_jsonl" "$translated_json"; then
                echo "[FAIL] $locale_name: unable to translate multi-line source"
                rm -f "$batch_jsonl" "$translated_json"
                continue
            fi

            if ! apply_translation_batch "$locale_file" "$batch_jsonl" "$translated_json"; then
                echo "[FAIL] $locale_name: unable to apply multi-line translation"
                rm -f "$batch_jsonl" "$translated_json"
                continue
            fi

            translated_total=$((translated_total + 1))
            rm -f "$batch_jsonl" "$translated_json"
        done < "$multi_targets"
    fi

    local remaining_single remaining_multi remaining_total
    generate_targets "$locale_file" "$single_targets" "$multi_targets"
    remaining_single="$(count_lines "$single_targets")"
    remaining_multi="$(count_lines "$multi_targets")"
    remaining_total=$((remaining_single + remaining_multi))

    echo "[DONE] $locale_name: translated $translated_total source string(s), remaining $scan_label=$remaining_total"
}

main() {
    local locale_file
    echo "Locale files to inspect: $(find "$localization_dir" -type f -name '*.json' | wc -l | tr -d '[:space:]')"
    echo "Batch size: $batch_size"

    while IFS= read -r locale_file; do
        case "$(basename "$locale_file")" in
            "$source_file")
                continue
                ;;
        esac

        if [[ ! "$(basename "$locale_file")" =~ $locale_file_pattern ]]; then
            continue
        fi

        if [[ -n "$target_locales_csv" ]]; then
            case "$target_locales_csv" in
                *,"$(basename "$locale_file")",*)
                    ;;
                *)
                    continue
                    ;;
            esac
        fi

        process_locale "$locale_file" || true
    done < <(find "$localization_dir" -type f -name '*.json' | sort)
}

main "$@"
