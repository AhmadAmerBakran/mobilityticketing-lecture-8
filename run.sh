#!/usr/bin/env bash
set -euo pipefail
cd /lab
export PGUSER="${POSTGRES_USER:-mobility}"
export PGDATABASE="${POSTGRES_DB:-mobility_l08}"
export PGOPTIONS="-c timezone=UTC"

psql_lab() { psql -X -v ON_ERROR_STOP=1 -P pager=off "$@"; }

query() {
    psql_lab -v route_id="$2" -v query_day=2026-10-23 -v result_limit="$3" \
        -A -t -F '|' -f "queries/$1.sql"
}

plan() {
    { printf 'explain (analyze, buffers)\n'; cat "queries/$1.sql"; } |
        psql_lab -v route_id="$2" -v query_day=2026-10-23 -v result_limit=20
}

command="${1:-help}"
case "$command" in
    reset)
        psql_lab -f database/setup.sql
        ;;
    run|measure)
        name="${2:-baseline}"
        route="${3:-R-7}"
        case "$name" in baseline|candidate) ;; *) echo 'Use baseline or candidate.' >&2; exit 2;; esac
        case "$route" in R-7|R-0) ;; *) echo 'Use R-7 or R-0.' >&2; exit 2;; esac
        if [[ "$command" == run ]]; then
            query "$name" "$route" 20
        else
            printf 'Query: %s | Route: %s | UTC day: 2026-10-23\n' "$name" "$route"
            printf 'Warm-up (not recorded)\n'
            plan "$name" "$route" > /dev/null
            for run in 1 2 3 4 5; do
                printf '\nMeasured run %s\n' "$run"
                plan "$name" "$route"
            done
        fi
        ;;
    indexes)
        psql_lab -f queries/indexes.sql
        psql_lab -c "select indexname, indexdef,
                     pg_size_pretty(pg_relation_size(format('%I.%I', schemaname, indexname)::regclass)) as size
                     from pg_indexes where schemaname='lab08' and tablename='trips'
                     order by indexname;"
        ;;
    check)
        for route in R-7 R-0; do
            for limit in 20 NULL; do
                expected="$(query baseline "$route" "$limit")"
                actual="$(query candidate "$route" "$limit")"
                case "$route:$limit" in R-7:NULL) count=38;; R-0:NULL) count=991;; *) count=20;; esac
                mapfile -t expected_rows <<< "$expected"
                if [[ -z "$expected" || "${#expected_rows[@]}" -ne "$count" ]]; then
                    printf 'FAIL: baseline fixture count for %s, LIMIT %s. Run reset.\n' "$route" "$limit" >&2
                    exit 1
                fi
                if [[ "$expected" != "$actual" ]]; then
                    printf 'FAIL: %s, LIMIT %s. Candidate results or their order changed.\n' "$route" "$limit" >&2
                    exit 1
                fi
                printf 'PASS: %s, LIMIT %s. Same %s rows in the same order.\n' "$route" "$limit" "$count"
            done
        done
        ;;
    partitions)
        psql_lab -f queries/partitioning.sql
        ;;
    *)
        printf '%s\n' 'Commands: reset | run baseline|candidate R-7|R-0 | measure baseline|candidate R-7|R-0 | indexes | check | partitions'
        ;;
esac
