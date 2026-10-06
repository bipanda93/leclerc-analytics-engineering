select jour
from {{ ref('mart_tendances_jour') }}
where ipc_alimentation is null
  and date_trunc('month', jour) <= (
      select max(observation_date) from {{ ref('stg_insee__conjoncture') }}
  )
