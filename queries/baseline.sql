-- Keep this original query unchanged. The helper supplies the three variables.
select id, route_id, scheduled_departure_utc, status
from lab08.trips
where route_id = :'route_id'
  and status = 'Scheduled'
  and (scheduled_departure_utc at time zone 'UTC')::date = :'query_day'::date
order by scheduled_departure_utc, id
limit :result_limit;
