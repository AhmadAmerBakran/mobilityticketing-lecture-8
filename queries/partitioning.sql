-- The plain and partitioned tables contain the same 120,000 events.
-- First check that both queries return the same number.
select 'plain' as layout, count(*) as october_events
from lab08.validations_plain
where validated_utc >= timestamptz '2026-10-01 00:00:00+00'
  and validated_utc < timestamptz '2026-11-01 00:00:00+00'
union all
select 'monthly', count(*)
from lab08.validations_by_month
where validated_utc >= timestamptz '2026-10-01 00:00:00+00'
  and validated_utc < timestamptz '2026-11-01 00:00:00+00';

-- A report for one UTC month.
explain (analyze, buffers)
select count(*)
from lab08.validations_plain
where validated_utc >= timestamptz '2026-10-01 00:00:00+00'
  and validated_utc < timestamptz '2026-11-01 00:00:00+00';

explain (analyze, buffers)
select count(*)
from lab08.validations_by_month
where validated_utc >= timestamptz '2026-10-01 00:00:00+00'
  and validated_utc < timestamptz '2026-11-01 00:00:00+00';

-- Support needs the history of one ticket but does not know its dates.
select 'plain' as layout, count(*) as ticket_100_events
from lab08.validations_plain where ticket_id = 100
union all
select 'monthly', count(*)
from lab08.validations_by_month where ticket_id = 100;

-- Zero differences means the ticket-history rows match, including duplicates.
select count(*) as different_ticket_history_rows
from (
    (select id, ticket_id, validated_utc from lab08.validations_plain where ticket_id = 100
     except all
     select id, ticket_id, validated_utc from lab08.validations_by_month where ticket_id = 100)
    union all
    (select id, ticket_id, validated_utc from lab08.validations_by_month where ticket_id = 100
     except all
     select id, ticket_id, validated_utc from lab08.validations_plain where ticket_id = 100)
) differences;

explain (analyze, buffers)
select id, ticket_id, validated_utc
from lab08.validations_plain
where ticket_id = 100
order by validated_utc, id;

explain (analyze, buffers)
select id, ticket_id, validated_utc
from lab08.validations_by_month
where ticket_id = 100
order by validated_utc, id;
