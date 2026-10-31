# Departure search measurements

23 October 2026, UTC. PostgreSQL 17, 120,008 trips. The baseline and rewritten queries return the same ordered rows for the first 20 and the full day on R-7 and R-0.

The timings below use one warm-up and five measured executions per query. The range is the smallest to largest `Execution Time`. Buffer values come from the top plan node and are not summed across nodes.

## Measurements

Not measured yet. The repository's benchmark workflow records the raw plans here and fills this table.

## Index choice

The first candidate indexes `route_id` alone. It can narrow the route search, but it cannot supply the departure-time ordering. A sort may still be needed.

The selected index is `(route_id, scheduled_departure_utc, id)` restricted to `status = 'Scheduled'`. The equality condition comes first, followed by the UTC range and the two ordering columns. This allows an ordered index scan to stop after the first 20 matches without sorting a whole day. The partial predicate excludes cancelled trips. The primary-key index remains in place.

A route-only index is a reasonable comparison but not the index I would keep for this screen. The plan and measurements above are the final check on whether that choice helps in practice, especially for the busier R-0 route.

An additional B-tree takes disk space and makes writes more expensive. Inserts of scheduled trips and changes to their route or departure time update the index. Cancelling a scheduled trip removes it from the partial index; changing a cancelled trip back to scheduled adds it.

## AI check

Prompt used for a second opinion:

> PostgreSQL 17 has `lab08.trips(id bigint primary key, route_id text, scheduled_departure_utc timestamptz, status text)`. The search selects id, route_id, scheduled_departure_utc and status, filters one route, `status = 'Scheduled'` and one UTC day's half-open departure range, orders by scheduled_departure_utc and id, and limits to 20. The existing index is the primary key on id. The baseline reads the date by casting `(scheduled_departure_utc at time zone 'UTC')::date`; its execution plans are saved in `docs/baseline-r7.txt` and `docs/baseline-r0.txt`. Suggest one B-tree index to test against an index on route_id alone, and explain the likely ordering and write costs.

Suggested index: a partial B-tree on `(route_id, scheduled_departure_utc, id)` for scheduled trips. I accepted it as the second candidate because it matches both the filter and ordering. The results above, not the suggestion alone, decide which index to keep.

## Monthly validation history

The supplied partitioning script compares the ordinary table with September, October and November partitions.

| Read | Expected result | What the plan means |
| --- | --- | --- |
| October count | 40,889 in both tables | The UTC month bounds allow pruning to `validations_oct`. The unpartitioned table is scanned or indexed as one table. |
| Ticket 100 | 12 in both tables; zero row differences | No date predicate is supplied, so all three monthly partitions must be considered. |

Monthly partitions are useful for date-bounded reports and for removing old months as units. They are less convincing for a ticket-history lookup without a date filter: partition pruning cannot remove a month, and each partition may need to be scanned. Partitioning itself does not create an index on `ticket_id`. If support lookups become the main concern, that indexing question should be assessed separately.

See `docs/partition-plans.txt` for the two layouts' actual plans once measurements have run.
