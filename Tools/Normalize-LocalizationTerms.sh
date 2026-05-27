#!/usr/bin/env zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
localization_dir="$repo_root/Localizations"
source_file="en-US.json"
locale_file_pattern='^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*\.json$'
translate_host_ip="${TRANSLATE_HOST_IP:-}"
term_tokens="${LOCALIZATION_TERMS:-Tweaks,Game Mode}"
unfinished_locales="${LOCALIZATION_UNFINISHED_LOCALES:-}"

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

tmp_root="${TMPDIR:-/tmp}/baseline-localization-terms"
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

translate_one() {
    local lang="$1"
    local source="$2"
    local response_file
    response_file="$(mktemp "$tmp_root/response.XXXXXX")"

    if ! translate_curl -G -L --fail --silent --show-error \
        --retry 5 --retry-all-errors --retry-delay 1 \
        --data-urlencode client=gtx \
        --data-urlencode sl=en \
        --data-urlencode tl="$lang" \
        --data-urlencode dt=t \
        --data-urlencode "q=$source" \
        'https://translate.googleapis.com/translate_a/single' \
        -o "$response_file"
    then
        rm -f "$response_file"
        return 1
    fi

    local translation
    if ! translation="$(python3 - "$response_file" <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
parts = payload[0] if isinstance(payload, list) and payload else []
print("".join(part[0] for part in parts))
PY
)"; then
        rm -f "$response_file"
        return 1
    fi

    rm -f "$response_file"
    printf '%s\n' "$translation"
}

normalize_locale() {
    local locale_file="$1"
    local locale_name
    locale_name="$(basename "$locale_file")"

    if [[ "$locale_name" == "$source_file" ]]; then
        return 0
    fi
    if [[ ! "$locale_name" =~ $locale_file_pattern ]]; then
        return 0
    fi
    if [[ "$locale_name" == en-*.json ]]; then
        return 0
    fi
    local skipped_locale
    for skipped_locale in ${(s:,:)unfinished_locales}; do
        if [[ -n "$skipped_locale" && "$locale_name" == "$skipped_locale" ]]; then
            echo "[SKIP] $locale_name is marked unfinished"
            return 0
        fi
    done

    local target_jsonl="$tmp_root/${locale_name}.targets.jsonl"
    python3 - "$en_path" "$locale_file" "$target_jsonl" "$term_tokens" <<'PY'
import json
import pathlib
import sys

en_path, locale_path, out_path, term_tokens_csv = sys.argv[1:5]
terms = [term.strip().lower() for term in term_tokens_csv.split(',') if term.strip()]
locked_keys_path = pathlib.Path(en_path).parent.parent / 'english_locked_keys.json'
locked_keys = set()
if locked_keys_path.is_file():
    locked_keys = set(json.loads(locked_keys_path.read_text(encoding='utf-8')))

def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding='utf-8-sig'))

en = load_json(en_path)
locale = load_json(locale_path)

by_source = {}
for key, source in en.items():
    if key in locked_keys:
        continue
    value = locale.get(key)
    if not isinstance(value, str):
        continue
    value_lower = value.lower()
    if any(term in value_lower for term in terms):
        by_source.setdefault(source, []).append(key)

with open(out_path, 'w', encoding='utf-8') as handle:
    for source, keys in by_source.items():
        handle.write(json.dumps({'source': source, 'keys': keys}, ensure_ascii=False) + '\n')
PY

    if [[ ! -s "$target_jsonl" ]]; then
        echo "[SKIP] $locale_name already has no term leaks"
        return 0
    fi

    local lang="${locale_name%.json}"
    local locale_translation_file="$tmp_root/${locale_name}.translations.jsonl"
    local translated_total=0

    echo "[START] $locale_name"

    while IFS= read -r line; do
        [[ -z "$line" ]] && continue

        local source keys_json translation
        source="$(jq -r '.source' <<<"$line")"
        keys_json="$(jq -c '.keys' <<<"$line")"

        if ! translation="$(translate_one "$lang" "$source")"; then
            echo "[FAIL] $locale_name: translation failed for source: $source"
            continue
        fi

        printf '%s\t%s\n' "$keys_json" "$translation" >> "$locale_translation_file"
        translated_total=$((translated_total + 1))
    done < "$target_jsonl"

    if [[ "$translated_total" -eq 0 ]]; then
        echo "[SKIP] $locale_name no successful translations"
        return 0
    fi

    python3 - "$locale_file" "$locale_translation_file" <<'PY'
import json
import pathlib
import sys

locale_path, translation_path = sys.argv[1:3]
locale = json.loads(pathlib.Path(locale_path).read_text(encoding='utf-8-sig'))

with open(translation_path, encoding='utf-8') as handle:
    for line in handle:
        line = line.rstrip('\n')
        if not line:
            continue
        keys_json, translation = line.split('\t', 1)
        keys = json.loads(keys_json)
        for key in keys:
            locale[key] = translation

pathlib.Path(locale_path).write_text(json.dumps(locale, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
PY

    local remaining_jsonl
    remaining_jsonl="$tmp_root/${locale_name}.remaining.jsonl"
    python3 - "$en_path" "$locale_file" "$remaining_jsonl" "$term_tokens" <<'PY'
import json
import pathlib
import sys

en_path, locale_path, out_path, term_tokens_csv = sys.argv[1:5]
terms = [term.strip().lower() for term in term_tokens_csv.split(',') if term.strip()]

def load_json(path):
    return json.loads(pathlib.Path(path).read_text(encoding='utf-8-sig'))

en = load_json(en_path)
locale = load_json(locale_path)

by_source = {}
for key, source in en.items():
    value = locale.get(key)
    if not isinstance(value, str):
        continue
    value_lower = value.lower()
    if any(term in value_lower for term in terms):
        by_source.setdefault(source, []).append(key)

with open(out_path, 'w', encoding='utf-8') as handle:
    for source, keys in by_source.items():
        handle.write(json.dumps({'source': source, 'keys': keys}, ensure_ascii=False) + '\n')
PY

    local remaining_count
    remaining_count="$(wc -l < "$remaining_jsonl" | tr -d '[:space:]')"
    echo "[DONE] $locale_name: translated $translated_total source string(s), remaining term leaks=$remaining_count"
}

main() {
    local locale_file
    echo "Locale files to inspect: $(find "$localization_dir" -type f -name '*.json' | wc -l | tr -d '[:space:]')"
    while IFS= read -r locale_file; do
        normalize_locale "$locale_file" || true
    done < <(find "$localization_dir" -type f -name '*.json' | sort)
}

main "$@"
