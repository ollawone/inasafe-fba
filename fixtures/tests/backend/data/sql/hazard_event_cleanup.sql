with find_hazard_event as (
    select * from hazard_event where source ilike '[test]%'
), delete_hazard_areas as (
    delete from hazard_areas where flood_map_id in (select distinct flood_map_id from find_hazard_event) returning *
), delete_hazard_area as (
    delete from hazard_area where id in (select distinct flooded_area_id from delete_hazard_areas) returning *
), delete_spreadsheet_reports as (
    delete from spreadsheet_reports where flood_event_id in (select distinct id from find_hazard_event) returning *
), delete_hazard_map as (
    delete from hazard_map where id in (select distinct flood_map_id from delete_hazard_areas) returning *
)
    delete from hazard_event where
    id in (
        select flood_event_id as id from delete_spreadsheet_reports
        union
        select distinct find_hazard_event.id as id from delete_hazard_map join find_hazard_event on find_hazard_event.flood_map_id = delete_hazard_map.id)
