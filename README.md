# MobilityTicketing lecture 8

Departure search tuning and monthly validation-history comparisons using PostgreSQL 17.

The database is disposable and independent of the earlier lectures. Docker and Docker Compose are required.

## Set up

```sh
docker compose up -d --wait postgres
docker compose exec -T postgres bash /lab/run.sh reset
docker compose exec -T postgres bash /lab/run.sh check
```

The fixture has 120,008 trips. The test date is 23 October 2026 in UTC. R-7 has 38 scheduled trips on that day and R-0 has 991. The search returns the first 20, ordered by departure time and ID.

## Compare the departure searches

Start with no experimental index. Save the baseline before measuring the rewritten query.

```sh
docker compose exec -T postgres bash /lab/run.sh measure baseline R-7 > docs/baseline-r7.txt
docker compose exec -T postgres bash /lab/run.sh measure baseline R-0 > docs/baseline-r0.txt
docker compose exec -T postgres bash /lab/run.sh check
docker compose exec -T postgres bash /lab/run.sh measure candidate R-7 > docs/rewrite-r7.txt
docker compose exec -T postgres bash /lab/run.sh measure candidate R-0 > docs/rewrite-r0.txt
```

Try the route-only index first. The SQL file selects that variant when `route_only` is supplied to psql.

```sh
docker compose exec -T postgres psql -X -v ON_ERROR_STOP=1 -U mobility -d mobility_l08 -v route_only=1 -f /lab/queries/indexes.sql
docker compose exec -T postgres bash /lab/run.sh check
docker compose exec -T postgres bash /lab/run.sh measure candidate R-7 > docs/route-r7.txt
docker compose exec -T postgres bash /lab/run.sh measure candidate R-0 > docs/route-r0.txt
```

Apply the selected index separately. This drops the route-only experiment and keeps the primary-key index.

```sh
docker compose exec -T postgres bash /lab/run.sh indexes > docs/index-sizes.txt
docker compose exec -T postgres bash /lab/run.sh check
docker compose exec -T postgres bash /lab/run.sh measure candidate R-7 > docs/index-r7.txt
docker compose exec -T postgres bash /lab/run.sh measure candidate R-0 > docs/index-r0.txt
```

Each measurement includes a warm-up and five executions. See `docs/evidence.md` for the comparison.

## Validation history

```sh
docker compose exec -T postgres bash /lab/run.sh partitions > docs/partition-plans.txt
```

October should contain 40,889 events in both tables. Ticket 100 should have 12 events in each, with zero differences. The output includes execution plans for the October report and the ticket-history lookup.

To start over, run `docker compose exec -T postgres bash /lab/run.sh reset`. This rebuilds only the `lab08` schema and removes the experimental indexes.

The original fixture, baseline query, partitioning script and command helper are unchanged from the lecture starter.
