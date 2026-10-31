select id, route_id, scheduled_departure_utc, status
from lab08.trips
where route_id = :'route_id'
  and status = 'Scheduled'
  and scheduled_departure_utc >= (:'query_day'::date::timestamp at time zone 'UTC')
  and scheduled_departure_utc < ((:'query_day'::date + 1)::timestamp at time zone 'UTC')
order by scheduled_departure_utc, id
limit :result_limit;
