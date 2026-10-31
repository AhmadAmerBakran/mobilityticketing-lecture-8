# Departure search measurements

PostgreSQL 17 with the supplied 120,008-trip fixture. All searches use 23 October 2026 in UTC.

The baseline was measured before any additional index. I then measured the rewritten query, a route-only index and a partial multicolumn index. Each measurement had one warm-up and five recorded executions. The table uses the median `Execution Time` and the minimum and maximum times. Buffer counts are from the top node of the last plan, not the sum of every node. These timings are from one GitHub Actions runner, not a general performance guarantee.

## Measurements

| Route | Query | Median ms | Range ms | Plan nodes | Top-node hit / read buffers |
| --- | --- | ---: | ---: | --- | ---: |
| R-7 | Baseline | 7.671 | 7.503–8.497 | Seq Scan, Sort | 1007 / 0 |
| R-7 | UTC range | 6.574 | 6.544–6.657 | Seq Scan, Sort | 1007 / 0 |
| R-7 | Route-only | 1.800 | 1.744–1.837 | Bitmap Heap Scan, Bitmap Index Scan, Sort | 1011 / 0 |
| R-7 | Selected index | 0.132 | 0.125–0.157 | Index Scan | 23 / 0 |
| R-0 | Baseline | 13.818 | 13.734–13.906 | Seq Scan, Sort | 1007 / 0 |
| R-0 | UTC range | 6.665 | 6.573–6.848 | Seq Scan, Sort | 1007 / 0 |
| R-0 | Route-only | 6.809 | 6.719–6.952 | Seq Scan, Sort | 1007 / 0 |
| R-0 | Selected index | 0.130 | 0.121–0.141 | Index Scan | 24 / 0 |

Index sizes: route-only **832 kB**; selected **4408 kB**.

All four correctness checks passed after the rewrite and after each index. They compare the first 20 and the complete day for R-7 and R-0.

Raw plans: `baseline-*.txt`, `rewrite-*.txt`, `route-*.txt`, `index-*.txt` in this directory.

## What changed

The baseline plan read all 120,008 trips with a sequential scan and then sorted the matching rows. For R-7, it removed 119,970 rows during filtering before returning the first 20. Rewriting the date condition as a half-open UTC range made it usable by a B-tree index, but it still used a sequential scan and a sort until an index was added.

With an index on `route_id` alone, R-7 used a bitmap heap scan and a sort. PostgreSQL still chose a sequential scan and a top-N sort for R-0. This is why the route-only index was not enough for the busier route.

With the partial multicolumn index, both routes used an ordered index scan without a separate sort. The top-node shared buffer hits were 23 for R-7 and 24 for R-0, compared with 1,007 for the baseline plans. No shared reads were reported in these warm runs.

The correctness checks passed after every change. Both routes matched the baseline for the first 20 and the full day (38 trips on R-7; 991 on R-0), in the same order. This includes the departure at `00:00:00`, the final microsecond before midnight and exclusion of the following day's midnight and cancelled departures.

## Index choice

I would keep `trips_scheduled_route_departure_idx`:

```sql
create index trips_scheduled_route_departure_idx
    on lab08.trips (route_id, scheduled_departure_utc, id)
    where status = 'Scheduled';
```

The `route_id` equality comes first, followed by the time range and the ordering by time and ID. The partial predicate keeps cancelled trips out of this index.

I would not keep `trips_route_only_idx`. It occupies 832 kB and helped R-7, but not R-0. The selected index is larger at 4,408 kB, yet avoids both the large scan and sort for these searches. The primary-key index was not changed.

An extra index also costs write work. A new scheduled trip adds an entry. A changed route or departure time moves its entry, and cancelling the trip removes it from this partial index. The larger index also needs more storage and maintenance.

## AI check

I used the following question for a second opinion on an index candidate:

> PostgreSQL 17. The table is `lab08.trips(id bigint primary key, route_id text not null, scheduled_departure_utc timestamptz not null, status text not null)`. Its only starting index is `trips_pkey` on `id`.
>
> The search is:
>
> ```sql
> select id, route_id, scheduled_departure_utc, status
> from lab08.trips
> where route_id = :'route_id'
>   and status = 'Scheduled'
>   and scheduled_departure_utc >= (:'query_day'::date::timestamp at time zone 'UTC')
>   and scheduled_departure_utc < ((:'query_day'::date + 1)::timestamp at time zone 'UTC')
> order by scheduled_departure_utc, id
> limit :result_limit;
> ```
>
> For R-7, the original query's plan was `Limit -> Sort -> Seq Scan on trips`, with 38 matching rows and 119,970 rows removed by the filter. Its top node had 1,007 shared buffer hits; the median execution time was 7.671 ms. R-0 also used `Limit -> Sort -> Seq Scan` and had a 13.818 ms median. Suggest one index worth testing against a single-column index on `route_id`. Consider the ordering, scheduled status and cost of updates.

The suggestion was a partial B-tree on `(route_id, scheduled_departure_utc, id)` restricted to scheduled trips. I tested it against the route-only index rather than accepting it on the suggestion alone. The scan types, sort operations, buffers and median times above supported keeping it.

## Monthly validation history

The supplied script produced the same data in both layouts: 40,889 October events, 12 events for ticket 100 and zero differences between the two sets of ticket-history rows.

| Read | Ordinary table | Monthly partitions |
| --- | --- | --- |
| October count | `Seq Scan` on `validations_plain`, 79,111 rows filtered out, 765 shared hits, 8.686 ms | Only `validations_oct` scanned, 261 shared hits, 5.130 ms |
| Ticket 100 history | `Seq Scan` on `validations_plain` and `Sort`, 771 shared hits, 4.575 ms | `Append` of scans on `validations_sep`, `validations_oct`, `validations_nov`, then `Sort`; 766 shared hits, 4.878 ms |

These partition timings are single `EXPLAIN ANALYZE` runs, not five-run medians. The actual plans are in `docs/partition-plans.txt`.

The October report can prune September and November because the time predicate stays inside October's partition boundaries. The ticket lookup only filters on `ticket_id`; without a time range, PostgreSQL must consider every month. Its 12 events were distributed as 4 in September, 3 in October and 5 in November.

I would use monthly partitions if month-based reports and retention matter. Removing an old month can then be handled by detaching or dropping its partition instead of deleting its rows individually. For ticket support alone, monthly partitioning does not solve the lookup: the table has no index on `ticket_id`, so all months were scanned. Partition management also adds some complexity.
