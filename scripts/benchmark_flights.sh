#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
input=${1:-"$repo_root/data/flights.csv"}
stamp=$(date -u +%Y%m%dT%H%M%SZ)
out_dir="$repo_root/benchmarks/$stamp"
tree="$out_dir/tree"
mkdir -p "$out_dir"

run_time() {
  local label=$1
  shift
  local stdout_file="$out_dir/$label.out"
  local time_file="$out_dir/$label.time"

  /usr/bin/time -p "$@" > "$stdout_file" 2> "$time_file"
  awk -v label="$label" '
    $1 == "real" { real = $2 }
    $1 == "user" { user = $2 }
    $1 == "sys" { sys = $2 }
    END { printf "%s,real=%s,user=%s,sys=%s\n", label, real, user, sys }
  ' "$time_file" >> "$out_dir/timings.csv"
}

count_file() {
  wc -l < "$1" | tr -d '[:space:]'
}

printf 'benchmark,real,user,sys\n' > "$out_dir/timings.csv"

run_time build \
  "$repo_root/bin/kdsplit" -t, --header --stable \
  -k 2,2n -k 3,3n -k 14,14 \
  --max-depth 8 --min-rows 10000 --parallel-depth 1 \
  --output-dir "$tree" --quiet "$input"

cat > "$out_dir/queries.tsv" <<'EOF'
summer_lax	2:6:8	14:LAX:LAX
january	2:1:1
midmonth	3:10:20
summer_lax_midmonth	2:6:8	3:10:20	14:LAX:LAX
EOF

printf 'query,kdsearch_rows,awk_rows\n' > "$out_dir/counts.csv"

while IFS=$'\t' read -r name r1 r2 r3; do
  [[ -n "$name" ]] || continue
  kd_args=()
  awk_pred='NR > 1'

  for range in "$r1" "$r2" "$r3"; do
    [[ -n "${range:-}" ]] || continue
    field=${range%%:*}
    rest=${range#*:}
    low=${rest%%:*}
    high=${rest#*:}
    kd_args+=(--range "$range")
    if [[ -n "$low" ]]; then
      if [[ "$field" == "2" || "$field" == "3" ]]; then
        awk_pred+=" && \$$field + 0 >= $low"
      else
        awk_pred+=" && \$$field >= \"$low\""
      fi
    fi
    if [[ -n "$high" ]]; then
      if [[ "$field" == "2" || "$field" == "3" ]]; then
        awk_pred+=" && \$$field + 0 <= $high"
      else
        awk_pred+=" && \$$field <= \"$high\""
      fi
    fi
  done

  run_time "kdsearch_$name" "$repo_root/bin/kdsearch" -t, --quiet "${kd_args[@]}" "$tree"
  run_time "awk_$name" awk -F, "$awk_pred" "$input"

  kd_rows=$(count_file "$out_dir/kdsearch_$name.out")
  awk_rows=$(count_file "$out_dir/awk_$name.out")
  printf '%s,%s,%s\n' "$name" "$kd_rows" "$awk_rows" >> "$out_dir/counts.csv"
  rm -f "$out_dir/kdsearch_$name.out" "$out_dir/awk_$name.out"
done < "$out_dir/queries.tsv"

find "$tree" -name data -exec sh -c 'for file do printf "%s %s\n" "$(wc -l < "$file" | tr -d "[:space:]")" "$file"; done' sh {} + > "$out_dir/node_rows.txt"
find "$tree" -name split.meta | wc -l | tr -d '[:space:]' > "$out_dir/node_count.txt"

printf 'benchmark_dir=%s\n' "$out_dir"
printf 'timings=%s\n' "$out_dir/timings.csv"
printf 'counts=%s\n' "$out_dir/counts.csv"
