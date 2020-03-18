drop materialized view if exists mv_flood_event_world_pop;
create materialized view mv_flood_event_world_pop as
WITH hazard_intersections AS (
    SELECT a_1.geometry,
           d_1.id AS flood_event_id,
           a_1.depth_class
    FROM hazard_area a_1
             JOIN hazard_areas b_1 ON a_1.id = b_1.flooded_area_id
             JOIN hazard_map c ON c.id = b_1.flood_map_id
             JOIN hazard_event d_1 ON d_1.flood_map_id = c.id
),
     hazard_admin_intersections as (
         select
            st_intersection(a.geometry, b.geom) as geometry,
            a.flood_event_id,
            a.depth_class,
            b.dc_code,
            b.sub_dc_code,
            b.village_code
         from hazard_intersections a
            join village b on st_intersects(a.geometry, b.geom)
     ),
     stats AS (
         SELECT row_number() OVER ()                                        AS id,
                st_summarystatsagg(st_clip(rast, geometry), 1, true) as stats,
                a.flood_event_id,
                a.depth_class,
                a.geometry,
                a.dc_code,
                a.sub_dc_code,
                a.village_code
         FROM hazard_admin_intersections a
            join world_pop b on st_intersects(a.geometry, b.rast)
         group by a.flood_event_id, a.depth_class, a.geometry, a.dc_code, a.sub_dc_code, a.village_code
     )
SELECT d.id,
       (d.stats).count as pop_count,
       (d.stats).sum as pop_sum,
       (d.stats).mean as pop_mean,
       (d.stats).stddev as pop_sttdev,
       (d.stats).min as pop_min,
       (d.stats).max as pop_max,
       d.flood_event_id,
       d.depth_class,
       d.geometry,
       d.dc_code,
       d.sub_dc_code,
       d.village_code
FROM stats d
WITH NO DATA;

comment on materialized view mv_flood_event_world_pop is 'This gives a summary of the population for each flood zone in a village region. It doesn''t aggregate per region';

create unique index if not exists mv_flood_event_world_pop_uidx on mv_flood_event_world_pop(id);
