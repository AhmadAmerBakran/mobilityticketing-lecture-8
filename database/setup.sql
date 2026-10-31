\set ON_ERROR_STOP on
-- Reset this lecture's disposable fixture only.
drop schema if exists lab08 cascade;
create schema lab08;
set time zone 'UTC';

create table lab08.trips (
    id bigint primary key,
    route_id text not null,
    scheduled_departure_utc timestamptz not null,
    status text not null check (status in ('Scheduled', 'Cancelled'))
);

-- R-0 has most of the trips. R-1 through R-9 share the rest.
insert into lab08.trips
select g,
       case when g % 4 = 0 then 'R-' || (1 + (g / 4) % 9)
            else 'R-0' end,
       timestamptz '2026-09-01 00:00:00+00'
           + ((g - 1) % 91) * interval '1 day'
           + ((g * 17) % 1440) * interval '1 minute',
       case when g % 13 = 0 then 'Cancelled' else 'Scheduled' end
from generate_series(1, 120000) g;

-- Boundary cases belong to the fixture, not to the student's query.
insert into lab08.trips values
    (900001, 'R-7', '2026-10-23 00:00:00+00',        'Scheduled'),
    (900002, 'R-7', '2026-10-24 00:00:00+00',        'Scheduled'),
    (900003, 'R-7', '2026-10-23 23:59:59.999999+00', 'Scheduled'),
    (900004, 'R-7', '2026-10-23 00:00:00+00',        'Cancelled'),
    (900011, 'R-0', '2026-10-23 00:00:00+00',        'Scheduled'),
    (900012, 'R-0', '2026-10-24 00:00:00+00',        'Scheduled'),
    (900013, 'R-0', '2026-10-23 23:59:59.999999+00', 'Scheduled'),
    (900014, 'R-0', '2026-10-23 00:00:00+00',        'Cancelled');

-- The two validation tables contain identical synthetic events and keys.
-- The key guarantees uniqueness of the pair (validated_utc, id), not id alone.
create table lab08.validations_plain (
    id bigint not null,
    ticket_id bigint not null,
    validated_utc timestamptz not null,
    primary key (validated_utc, id)
);

create table lab08.validations_by_month (
    id bigint not null,
    ticket_id bigint not null,
    validated_utc timestamptz not null,
    primary key (validated_utc, id)
) partition by range (validated_utc);

create table lab08.validations_sep
partition of lab08.validations_by_month
for values from ('2026-09-01 00:00:00+00') to ('2026-10-01 00:00:00+00');

create table lab08.validations_oct
partition of lab08.validations_by_month
for values from ('2026-10-01 00:00:00+00') to ('2026-11-01 00:00:00+00');

create table lab08.validations_nov
partition of lab08.validations_by_month
for values from ('2026-11-01 00:00:00+00') to ('2026-12-01 00:00:00+00');

insert into lab08.validations_plain
select g,
       1 + (g - 1) % 10000,
       timestamptz '2026-09-01 00:00:00+00'
           + ((g - 1) % 91) * interval '1 day'
           + ((g * 37) % 86400) * interval '1 second'
from generate_series(1, 120000) g;

insert into lab08.validations_by_month
select * from lab08.validations_plain;

analyze lab08.trips;
analyze lab08.validations_plain;
analyze lab08.validations_by_month;

select count(*) as trips from lab08.trips;
select route_id, count(*) as scheduled_on_23_october
from lab08.trips
where route_id in ('R-7', 'R-0')
  and status = 'Scheduled'
  and (scheduled_departure_utc at time zone 'UTC')::date = date '2026-10-23'
group by route_id
order by route_id;

select to_char(validated_utc at time zone 'UTC', 'YYYY-MM') as month,
       count(*) as validations
from lab08.validations_plain
group by month
order by month;
