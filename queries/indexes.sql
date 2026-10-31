-- Pass -v route_only=1 to psql to test the single-column index.
-- Without that variable, the selected partial index is installed.
drop index if exists lab08.trips_route_only_idx;
drop index if exists lab08.trips_scheduled_route_departure_idx;

\if :{?route_only}
create index trips_route_only_idx
    on lab08.trips (route_id);
\else
create index trips_scheduled_route_departure_idx
    on lab08.trips (route_id, scheduled_departure_utc, id)
    where status = 'Scheduled';
\endif
