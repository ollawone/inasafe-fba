--
-- PostgreSQL database dump
--

-- Dumped from database version 11.6 (Debian 11.6-1.pgdg100+1)
-- Dumped by pg_dump version 11.6 (Debian 11.6-1.pgdg100+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA IF NOT EXISTS public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';



--
-- Name: clean_tables(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.clean_tables() RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE osm_tables CURSOR FOR
    SELECT table_name
    FROM information_schema.tables
    WHERE table_schema='public'
    AND table_type='BASE TABLE'
    AND table_name LIKE 'osm_%';
BEGIN
    FOR osm_table IN osm_tables LOOP
        EXECUTE 'DELETE FROM ' || quote_ident(osm_table.table_name) || ' WHERE osm_id IN (
            SELECT DISTINCT osm_id
            FROM ' || quote_ident(osm_table.table_name) || '
            LEFT JOIN clip ON ST_Intersects(geometry, geom)
            WHERE clip.ogc_fid IS NULL)
        ;';
    END LOOP;
END;
$$;





--
-- Name: flood_event_forecast_list_f(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flood_event_forecast_list_f(acquisition_date_start timestamp without time zone, acquisition_date_end timestamp without time zone) RETURNS TABLE(total_forecast bigint, lead_time bigint, trigger_status_id integer)
    LANGUAGE plpgsql
    AS $$
begin return query
         select count(a.id) as total_forecast,
               a.lead_time, MAX(a.trigger_status) as trigger_status_id
        from (
            select id,
                   extract(day from forecast_date - acquisition_date)::bigint as lead_time, trigger_status
            from hazard_event
            where (
                acquisition_date >= acquisition_date_start
                    and acquisition_date < acquisition_date_end)
            ) as a
        group by a.lead_time;
    end;
$$;


--
-- Name: flood_event_forecast_range_list_f(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flood_event_forecast_range_list_f(acquisition_date_start timestamp without time zone, acquisition_date_end timestamp without time zone) RETURNS TABLE(total_forecast bigint, forecast_date_str text, acquisition_date_str text, trigger_status_id integer)
    LANGUAGE plpgsql
    AS $$
begin return query
         select count(a.id) as total_forecast,
               a.forecast_date_str as forecast_date_str, 
               a.acquisition_date_str as acquisition_date_str, MAX(a.trigger_status) as trigger_status_id
        from (
            select id, to_char(forecast_date, 'YYYY-MM-DD') as forecast_date_str, to_char(acquisition_date, 'YYYY-MM-DD') as acquisition_date_str, trigger_status from flood_event
            where (acquisition_date >= acquisition_date_start and acquisition_date < acquisition_date_end AND forecast_date IS NOT NULL)
 ) as a
        group by a.forecast_date_str, a.acquisition_date_str ORDER BY a.acquisition_date_str;
    end;
$$;


--
-- Name: flood_event_historical_forecast_list_f(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flood_event_historical_forecast_list_f(forecast_date_range_start timestamp without time zone, forecast_date_range_end timestamp without time zone) RETURNS TABLE(total_forecast bigint, relative_forecast_date bigint, minimum_lead_time bigint, maximum_lead_time bigint, trigger_status_id integer)
    LANGUAGE plpgsql
    AS $$
begin return query
--         historical forecast only
    select
        count(a.id) as total_forecast,
        a.relative_forecast_date,
        min(a.lead_time) as minimum_lead_time,
        max(a.lead_time) as maximum_lead_time,
        max(a.trigger_status) as trigger_status_id
    from
    (select
        hazard_event.id,
           extract(day from forecast_date - forecast_date_range_start)::bigint as relative_forecast_date,
            extract(day from forecast_date - acquisition_date)::bigint as lead_time,
        hazard_event.trigger_status
    from hazard_event
    where forecast_date >= forecast_date_range_start and forecast_date < forecast_date_range_end) as a
    group by a.relative_forecast_date;
    end;
$$;


--
-- Name: flood_event_newest_forecast_f(timestamp without time zone, timestamp without time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flood_event_newest_forecast_f(forecast_date_start timestamp without time zone, forecast_date_end timestamp without time zone) RETURNS TABLE(forecast_date_str text, acquisition_date_str text, trigger_status_id integer)
    LANGUAGE plpgsql
    AS $$
begin return query
        select distinct on (forecast_date_str) a.forecast_date_str, a.acquisition_date_str, a.trigger_status
        from (
            select id, to_char(forecast_date, 'YYYY-MM-DD') as forecast_date_str, to_char(acquisition_date, 'YYYY-MM-DD') as acquisition_date_str, trigger_status from flood_event
            where forecast_date >= forecast_date_start and forecast_date < forecast_date_end AND forecast_date IS NOT NULL
 ) as a ORDER BY a.forecast_date_str DESC, a.acquisition_date_str DESC;
    end;
$$;


--
-- Name: flood_event_spreadsheet(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.flood_event_spreadsheet(hazard_event_id integer) RETURNS TABLE(spreadsheet_content text)
    LANGUAGE plpgsql
    AS $$
begin return query
        select encode(spreadsheet, 'base64') as spreadsheet_content from spreadsheet_reports where flood_event_id=hazard_event_id;
    end;
$$;




--
-- Name: hazard_event_spreadsheet(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.hazard_event_spreadsheet(hazard_event_id integer) RETURNS TABLE(spreadsheet_content text)
    LANGUAGE plpgsql
    AS $$
begin return query
        select encode(spreadsheet, 'base64') as spreadsheet_content from spreadsheet_reports where flood_event_id=hazard_event_id;
    end;
$$;


--
-- Name: kartoza_building_area_mapper(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_building_area_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    NEW.building_area:=ST_Area(new.geometry::GEOGRAPHY) ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_building_area_score_mapper(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_building_area_score_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
  SELECT
        CASE
            WHEN new.building_area <= 10 THEN 1
            WHEN new.building_area > 10 and new.building_area <= 30 THEN 0.7
            WHEN new.building_area > 30 and new.building_area <= 100 THEN 0.5
            WHEN new.building_area > 100 THEN 0.3
            ELSE 0.3
        END
  INTO new.building_area_score
  FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_building_materials_mapper(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_building_materials_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    SELECT

    CASE
        WHEN new."building:material" ILIKE 'brick%' THEN 0.5
        WHEN new."building:material" = 'concrete' THEN 0.1
        ELSE 0.3
    END
    INTO new.building_material_score
    FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_building_recode_mapper(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_building_recode_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
     SELECT

        CASE
            WHEN new.building_type = 'Clinic/Doctor' THEN 0.7
            WHEN new.building_type = 'Commercial' THEN 0.7
            WHEN new.building_type = 'School' THEN 1
            WHEN new.building_type = 'Government' THEN 0.7
            WHEN new.building_type ILIKE 'Place of Worship%' THEN 0.5
            WHEN new.building_type = 'Residential' THEN 1
            WHEN new.building_type = 'Police Station' THEN 0.7
            WHEN new.building_type = 'Fire Station' THEN 0.7
            WHEN new.building_type = 'Hospital' THEN 0.7
            WHEN new.building_type = 'Supermarket' THEN 0.7
            WHEN new.building_type = 'Sports Facility' THEN 0.3
            WHEN new.building_type = 'University/College' THEN 1.0
            ELSE 0.3
        END
     INTO new.building_type_score
     FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_building_types_mapper(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_building_types_mapper() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    SELECT
    CASE
           WHEN new.amenity ILIKE '%school%' OR new.amenity ILIKE '%kindergarten%' THEN 'School'
           WHEN new.amenity ILIKE '%university%' OR new.amenity ILIKE '%college%' THEN 'University/College'
           WHEN new.amenity ILIKE '%government%' THEN 'Government'
           WHEN new.amenity ILIKE '%clinic%' OR new.amenity ILIKE '%doctor%' THEN 'Clinic/Doctor'
           WHEN new.amenity ILIKE '%hospital%' THEN 'Hospital'
           WHEN new.amenity ILIKE '%fire%' THEN 'Fire Station'
           WHEN new.amenity ILIKE '%police%' THEN 'Police Station'
           WHEN new.amenity ILIKE '%public building%' THEN 'Public Building'
           WHEN new.amenity ILIKE '%worship%' and (religion ILIKE '%islam' or religion ILIKE '%muslim%')
               THEN 'Place of Worship - Islam'
           WHEN new.amenity ILIKE '%worship%' and new.religion ILIKE '%budd%' THEN 'Place of Worship - Buddhist'
           WHEN new.amenity ILIKE '%worship%' and new.religion ILIKE '%unitarian%' THEN 'Place of Worship - Unitarian'
           WHEN new.amenity ILIKE '%mall%' OR new.amenity ILIKE '%market%' THEN 'Supermarket'
           WHEN new.landuse ILIKE '%residential%' OR new.use = 'residential' THEN 'Residential'
           WHEN new.landuse ILIKE '%recreation_ground%' OR new.leisure IS NOT NULL AND new.leisure != '' THEN 'Sports Facility'
           -- run near the end
           WHEN new.amenity = 'yes' THEN 'Residential'
           WHEN new.use = 'government' AND new."type" IS NULL THEN 'Government'
           WHEN new.use = 'residential' AND new."type" IS NULL THEN 'Residential'
           WHEN new.use = 'education' AND new."type" IS NULL THEN 'School'
           WHEN new.use = 'medical' AND new."type" IS NULL THEN 'Clinic/Doctor'
           WHEN new.use = 'place_of_worship' AND new."type" IS NULL THEN 'Place of Worship'
           WHEN new.use = 'school' AND new."type" IS NULL THEN 'School'
           WHEN new.use = 'hospital' AND new."type" IS NULL THEN 'Hospital'
           WHEN new.use = 'commercial' AND new."type" IS NULL THEN 'Commercial'
           WHEN new.use = 'industrial' AND new."type" IS NULL THEN 'Industrial'
           WHEN new.use = 'utility' AND new."type" IS NULL THEN 'Utility'
           -- Add default type
           WHEN new."type" IS NULL THEN 'Residential'
        END
    INTO new.building_type
    FROM osm_buildings
    ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_fba_forecast_glofas(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_fba_forecast_glofas() RETURNS character varying
    LANGUAGE plpython3u
    AS $_$
import json
from collections import OrderedDict
from datetime import datetime, timedelta

from osgeo import ogr
from glofas.layer.reporting_point import ReportingPointAPI, ReportingPointResult

import requests


class GloFASForecast(object):

    TRIGGER_STATUS_NO_ACTIVATION = 0
    TRIGGER_STATUS_PRE_ACTIVATION = 1
    TRIGGER_STATUS_ACTIVATION = 2

    PROGRESS_IN_PROGRESS = 1
    PROGRESS_DONE = 2

    _default_point_layer_source = (
        'http://78.47.62.69/geoserver/kartoza/ows?service=WFS&version=1'
        '.0.0&request=GetFeature&typeName=kartoza:reporting_point'
        '&maxFeatures=50&outputFormat=application/json&srsName=EPSG:4326')
    _default_pre_activation_lead_time = 10
    _default_activation_lead_time = 3
    _default_pre_activation_eps_min_probability = 0
    _default_activation_eps_min_probability = 0
    # Note below, we want to preserve the order.
    # Increasing alert priority order
    # Mapping is the alert level into return period range
    _default_alert_level_return_period_mapping = OrderedDict(
        [
            (ReportingPointResult.ALERT_LEVEL_MEDIUM, [2, 5]),
            (ReportingPointResult.ALERT_LEVEL_HIGH, [5, 20]),
            (ReportingPointResult.ALERT_LEVEL_SEVERE, [20, 100]),
        ])
    # Minimum alert corresponds to the index of alert_level mapping above
    _default_pre_activation_minimum_alert = 1
    _default_activation_minimum_alert = 2
    # Impact limit
    _default_pre_activation_impact_limit = 0
    _default_activation_impact_limit = 0

    # Flood map query filter
    _default_postgrest_url = 'http://159.69.44.205:3000/'
    _default_flood_map_query_filter = 'flood_map?select=*,reporting_point(id,glofas_id)&reporting_point.glofas_id=eq.{station_id}&measuring_station_id=not.is.null&and=(return_period.gte.{return_period_min},return_period.lt.{return_period_max})'
    _default_plpy_query_flood_map_filter ='select flood_map.* from flood_map join reporting_point on flood_map.measuring_station_id = reporting_point.id where reporting_point.glofas_id = $1 and return_period >= $2 and return_period < $3'

    # Flood Forecast query filter
    _default_flood_forecast_event_query_filter = 'flood_event?select=id,flood_map_id,acquisition_date,forecast_date,source,notes,link,trigger_status,progress&acquisition_date=lt.{acquisition_date}&forecast_date=eq.{forecast_date}&source=eq.{source}&order=acquisition_date.desc'
    _default_plpy_flood_forecast_event_filter = 'select id,flood_map_id,acquisition_date,forecast_date,source,notes,link,trigger_status,progress from flood_event where acquisition_date < $1 and forecast_date = $2 and source = $3'

    # Flood forecast delete
    _default_flood_event_delete_query_filter = '?and=(flood_map_id.eq.{flood_map_id},acquisition_date.eq.{acquisition_date},forecast_date.eq.{forecast_date},source.eq.{source})'
    _default_plpy_flood_event_delete_filter = 'delete from flood_event where flood_map_id = $1 and acquisition_date = $2 and forecast_date = $3 and source = $4'

    # Flood Forecast insert
    _default_flood_event_insert_endpoint = 'flood_event?select=id,flood_map_id,acquisition_date,forecast_date,source,notes,link,trigger_status,progress'
    _default_plpy_flood_event_insert_query = 'insert into flood_event (flood_map_id, acquisition_date, forecast_date, source, notes, link, trigger_status, progress) select flood_map_id, acquisition_date, forecast_date, source, notes, link, trigger_status, progress from json_populate_recordset(null::flood_event, $1) returning id'

    # Impact query
    _default_impacted_village_query_filter = 'vw_village_impact?flood_event_id=eq.{flood_event_id}&impact_ratio=gte.{impact_limit}'

    # Region trigger status query
    _default_region_trigger_status_endpoint = '{region}_trigger_status'
    _default_region_trigger_status_delete_query_param = '?flood_event_id=eq.{flood_event_id}'
    _default_region_trigger_status_query_filter = '{region}_trigger_status?flood_event_id=eq.{flood_event_id}'

    # Administrative mapping
    _default_parent_administrative_mapping = 'mv_administrative_mapping?select={parent_region}_id,{child_region}_id&{child_region}_id=in.{child_ids}'

    def __init__(
            self,
            reporting_point_layer_source=None,
            pre_activation_lead_time=_default_pre_activation_lead_time,
            activation_lead_time=_default_activation_lead_time,
            pre_activation_eps_min_probability=_default_pre_activation_eps_min_probability,
            activation_eps_min_probability=_default_activation_eps_min_probability,
            alert_level_return_period_mapping=_default_alert_level_return_period_mapping,
            pre_activation_minimum_alert=_default_pre_activation_minimum_alert,
            activation_minimum_alert=_default_activation_minimum_alert,
            pre_activation_impact_limit=_default_pre_activation_impact_limit,
            activation_impact_limit=_default_activation_impact_limit,
            #  Query config
            use_plpy=False,
            postgrest_url=_default_postgrest_url,
            # Flood Map Query
            flood_map_query_filter=_default_flood_map_query_filter,
            plpy_query_flood_map_filter=_default_plpy_query_flood_map_filter,
            # Flood Event Query
            flood_event_query_filter=_default_flood_forecast_event_query_filter,
            plpy_flood_event_filter=_default_plpy_flood_forecast_event_filter,
            # Flood Event Deletion
            flood_event_delete_query_filter=_default_flood_event_delete_query_filter,
            plpy_flood_event_delete_filter=_default_plpy_flood_event_delete_filter,
            # Flood Event insertion
            flood_event_insert_endpoint=_default_flood_event_insert_endpoint,
            plpy_flood_event_insert_query=_default_plpy_flood_event_insert_query,
            # Impact limit query
            impacted_village_query_filter=_default_impacted_village_query_filter,
            # Region trigger status query
            region_trigger_status_endpoint=_default_region_trigger_status_endpoint,
            region_trigger_status_delete_query_param=_default_region_trigger_status_delete_query_param,
            region_trigger_status_query_filter=_default_region_trigger_status_query_filter,
            # Administrative mapping
            parent_administrative_mapping=_default_parent_administrative_mapping):
        self.api = ReportingPointAPI()
        self.point_layer_source = (
                reporting_point_layer_source
                or GloFASForecast._default_point_layer_source)
        self.pre_activation_lead_time = pre_activation_lead_time
        self.activation_lead_time = activation_lead_time
        self.pre_activation_eps_min_probability = pre_activation_eps_min_probability
        self.activation_eps_min_probability = activation_eps_min_probability
        self.alert_level_return_period_mapping = alert_level_return_period_mapping
        self.pre_activation_minimum_alert = pre_activation_minimum_alert
        self.activation_minimum_alert = activation_minimum_alert
        self.pre_activation_impact_limit = pre_activation_impact_limit
        self.activation_impact_limit = activation_impact_limit
        ##
        self.postgrest_url = postgrest_url
        self.flood_map_query_filter = flood_map_query_filter
        self.use_plpy = use_plpy
        self.plpy_query_flood_map_filter = plpy_query_flood_map_filter
        self.flood_event_query_filter = flood_event_query_filter
        self.plpy_flood_event_filter = plpy_flood_event_filter
        self.flood_event_insert_endpoint = flood_event_insert_endpoint
        self.plpy_flood_event_insert_query = plpy_flood_event_insert_query
        self.flood_event_delete_query_filter = flood_event_delete_query_filter
        self.plpy_flood_event_delete_filter = plpy_flood_event_delete_filter
        self.impacted_village_query_filter = impacted_village_query_filter
        self.region_trigger_status_endpoint = region_trigger_status_endpoint
        self.region_trigger_status_delete_query_param = region_trigger_status_delete_query_param
        self.region_trigger_status_query_filter = region_trigger_status_query_filter
        self.parent_administrative_mapping = parent_administrative_mapping
        ##
        self.feature_info = []
        self.flood_forecast_events = []

    def find_flood_map_plpy(self, station_id, return_period_min, return_period_max):
        import plpy

        plan = plpy.prepare(self.plpy_query_flood_map_filter,
                            ["int", "int", "int"])
        result = plpy.execute(plan, [station_id, return_period_min,
                                     return_period_max])

        if len(result) == 0:
            # We didn't found any flood map
            return None

        # We found the flood map
        row = result[0]
        return row['id']

    def find_flood_map_postgrest(
            self, station_id, return_period_min, return_period_max):
        query_param = self.flood_map_query_filter.format(
            station_id=station_id,
            return_period_min=return_period_min,
            return_period_max=return_period_max
        )
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=query_param)
        response = requests.get(url)
        try:
            flood_map_id = None
            result = response.json()
            flood_map_id = result[0]['id']
        finally:
            return flood_map_id

    def find_previous_flood_forecast_postgrest(
            self, forecast_date, maximum_acquisition_date, source):
        query_param = self.flood_event_query_filter.format(
            acquisition_date=maximum_acquisition_date,
            forecast_date=forecast_date,
            source=source)
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=query_param)
        response = requests.get(url)
        try:
            flood_event = None
            result = response.json()
            flood_event = result[0]
        finally:
            return flood_event

    def find_previous_flood_forecast_plpy(
            self, forecast_date, maximum_acquisition_date, source):
        import plpy

        plan = plpy.prepare(self.plpy_query_flood_map_filter,
                            ["timestamp", "timestamp", "varchar"])
        result = plpy.execute(
            plan, [maximum_acquisition_date.isoformat(), forecast_date.isoformat(), source])

        if len(result) == 0:
            # We didn't found any flood map
            return None

        # We found the flood map
        row = result[0]
        return row

    def _evaluate_flood_forecast_activation_candidate(
            self,
            current_flood_forecast,
            forecast_eps,
            relative_forecast_day,
            reporting_point_result,
            acquisition_date):
        total_alert_level = len(self.alert_level_return_period_mapping.keys())
        # Determine if alert level eligible for activation
        for alert_level_index in range(total_alert_level):

            alert_level = \
                list(self.alert_level_return_period_mapping)[
                    alert_level_index]
            return_period = \
                self.alert_level_return_period_mapping[alert_level]

            if alert_level_index < \
                    self.activation_minimum_alert:
                # skip if not eligible
                continue

            # Determine if there are significant forecast_eps with
            # sufficient lead time

            # see if it passes confidence threshold/probability
            # threshold
            forecast_value = forecast_eps[alert_level]
            if forecast_value < \
                    self.activation_eps_min_probability:
                # skip if probability is less than threshold
                continue

            # We have high enough probability, so proceed
            forecast_date = acquisition_date + timedelta(
                days=relative_forecast_day)

            # Find available corresponding flood map model from
            # database
            # Criteria is based on:
            #  - matching of return period in range
            #  - matching station id

            station_id = reporting_point_result.point_no
            return_period_min = return_period[0]
            return_period_max = return_period[1]

            if self.use_plpy:
                flood_map_id = self.find_flood_map_plpy(
                    station_id,
                    return_period_min,
                    return_period_max)
            else:
                flood_map_id = self.find_flood_map_postgrest(
                    station_id,
                    return_period_min,
                    return_period_max)

            # If we don't have flood map, skip
            if not flood_map_id:
                continue

            # The forecast_eps will have flood map and
            # is eligible for activation test
            # Determine eligibility based on previous pre-activation

            # Check previous forecast activation
            if self.use_plpy:
                flood_event = self.find_previous_flood_forecast_plpy(
                    forecast_date,
                    acquisition_date - timedelta(days=1),
                    current_flood_forecast['source'])
            else:
                flood_event = self.find_previous_flood_forecast_postgrest(
                    forecast_date,
                    acquisition_date - timedelta(days=1),
                    current_flood_forecast['source'])

            if not flood_event:
                # No previous forecast
                continue

            previous_trigger_status = flood_event['trigger_status_candidate']
            if not (
                    previous_trigger_status ==
                    GloFASForecast.TRIGGER_STATUS_PRE_ACTIVATION
                    or previous_trigger_status ==
                    GloFASForecast.TRIGGER_STATUS_ACTIVATION):
                # It will not trigger activation
                # Skip
                continue

            # This flood forecast_eps now an activation candidate
            # Because several days ago the forecast_eps has been in a
            # pre-activation trigger state
            # Define new flood forecast_eps definition
            current_flood_forecast = {
                'flood_map_id': flood_map_id,
                'acquisition_date': acquisition_date,
                'forecast_date': forecast_date,
                'source': 'GloFAS - Reporting Point',
                'alert_level_key': alert_level,
                'notes': 'Alert Warning Level: {alert_level}'.format(
                    alert_level=alert_level.upper()),
                'link': 'https://globalfloods.eu/',
                'trigger_status_candidate':
                    GloFASForecast.TRIGGER_STATUS_ACTIVATION
            }
            # This means, out of this loop, current flood forecast_eps is
            # from the highest severity available that passes
            # activation criteria
        return current_flood_forecast

    def _evaluate_flood_forecast_pre_activation_candidate(
            self,
            current_flood_forecast,
            forecast_eps,
            relative_forecaste_day,
            reporting_point_result,
            acquisition_date):
        # Determine if alert level eligible for pre activation
        total_alert_level = len(self.alert_level_return_period_mapping.keys())

        contexts = []
        for alert_level_index in range(total_alert_level):

            alert_level = \
                list(self.alert_level_return_period_mapping)[
                    alert_level_index]
            return_period = \
                self.alert_level_return_period_mapping[alert_level]

            if alert_level_index < self.pre_activation_minimum_alert:
                # skip if not eligible
                contexts.append('Skip because low alert level')
                continue

            # Determine if there are significant forecast_eps with
            # sufficient lead time

            # see if it passes confidence threshold/probability threshold
            forecast_value = forecast_eps[alert_level]
            if forecast_value < \
                    self.pre_activation_eps_min_probability:
                # skip if probability is less than threshold
                contexts.append('Skip because low probability')
                continue

            # We have high enough probability, so proceed
            forecast_date = acquisition_date + timedelta(
                days=relative_forecaste_day)

            # Find available corresponding flood map model from database
            # Criteria is based on:
            #  - matching of return period in range
            #  - matching station id

            station_id = reporting_point_result.point_no
            return_period_min = return_period[0]
            return_period_max = return_period[1]

            if self.use_plpy:
                flood_map_id = \
                    self.find_flood_map_plpy(
                        station_id,
                        return_period_min,
                        return_period_max)
            else:
                flood_map_id = \
                    self.find_flood_map_postgrest(
                        station_id,
                        return_period_min,
                        return_period_max)

            # If we don't have flood map, skip
            if not flood_map_id:
                contexts.append('Skip because flood map not found')
                continue

            # If we have flood map. Make a flood forecast_eps candidate
            current_flood_forecast = {
                'flood_map_id': flood_map_id,
                'acquisition_date': acquisition_date,
                'forecast_date': forecast_date,
                'source': 'GloFAS - Reporting Point',
                'alert_level_key': alert_level,
                'notes': 'Alert Warning Level: {alert_level}'.format(
                    alert_level=alert_level.upper()),
                'link': 'https://globalfloods.eu/',
                'trigger_status_candidate':
                    GloFASForecast.TRIGGER_STATUS_PRE_ACTIVATION,
            }
            # The forecast_eps is eligible for pre-activation
            # This means, out of this loop, current flood forecast_eps is
            # from the highest severity available that passes
            # pre-activation criteria

        return current_flood_forecast

    def push_flood_forecast_event_postgrest(self, flood_forecast_events):
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=self.flood_event_insert_endpoint)
        headers = {
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
        }
        # Filter only the needed column
        flood_events = [
            {
                'flood_map_id': v['flood_map_id'],
                'acquisition_date': v['acquisition_date'].isoformat(),
                'forecast_date': v['forecast_date'].isoformat(),
                'source': v['source'],
                'notes': v['notes'],
                'link': v['link'],
                'trigger_status': v['trigger_status_candidate'],
                # Progress 1 means, impact level has not been calculated
                'progress': GloFASForecast.PROGRESS_IN_PROGRESS
            }
            for v in flood_forecast_events
        ]
        json_string = json.dumps(flood_events)

        # The process needs to be idempotent, so delete matching forecast first
        query_param = self.flood_event_delete_query_filter
        for event in flood_events:
            delete_url = url + query_param.format(**event)
            requests.delete(delete_url)

        # Bulk inserts
        response = requests.post(
            url,
            data=json_string,
            headers=headers)
        # Get the returned ids
        created = response.json()

        return [c['id'] for c in created]

    def push_flood_forecast_event_plpy(self, flood_forecast_events):
        import plpy

        # Filter only the needed column
        flood_events = [
            {
                'flood_map_id': v['flood_map_id'],
                'acquisition_date': v['acquisition_date'].isoformat(),
                'forecast_date': v['forecast_date'].isoformat(),
                'source': v['source'],
                'notes': v['notes'],
                'link': v['link'],
                'trigger_status': v['trigger_status_candidate'],
                # Progress 1 means, impact level has not been calculated
                'progress': GloFASForecast.PROGRESS_IN_PROGRESS
            }
            for v in flood_forecast_events
        ]
        json_string = json.dumps(flood_events)

        # The process needs to be idempotent, so delete matching forecast first
        for event in flood_events:
            plan = plpy.prepare(
                self.plpy_flood_event_delete_filter,
                ["int", "timestamp", "timestamp", "varchar"])
            plpy.execute(plan,[
                event['flood_map_id'],
                event['acquisition_date'],
                event['forecast_date'],
                event['source']
            ])

        # We bulk insert the events
        plan = plpy.prepare(
            self.plpy_flood_event_insert_query, ["text"])
        result = plpy.execute(plan, [json_string])
        return result

    def fetch_forecast(self, acquisition_date=None):
        # Fetch forecast from GloFAS
        # Get point layer
        ds = ogr.Open(self.point_layer_source)
        point_layer = ds.GetLayer()
        # Get the forecast itself
        self.api.time = acquisition_date or self.api.time
        self.feature_info = self.api.get_feature_info(point_layer)

    def process_forecast(self):
        # determine current date
        today = self.api.time or datetime.today().replace(
            hour=0, minute=0, second=0, microsecond=0)

        flood_forecast_events = []

        # iterate thru all reporting points
        for info in self.feature_info:

            # Combine alert level and forecasted EPS values so we can iterate
            # for each date
            forecast_days = []
            for key, value in self.alert_level_return_period_mapping.items():
                eps_array = info.eps_array(key)
                for i in range(len(eps_array)):
                    eps = eps_array[i]
                    try:
                        forecast = forecast_days[i]
                    except:
                        forecast = {}

                    forecast[key] = eps
                    try:
                        forecast_days[i] = forecast
                    except:
                        forecast_days.append(forecast)

            # Iterate each date
            for i in range(len(forecast_days)):

                if forecast_days[i]['medium'] == 0:
                    continue

                # Get the forecast
                forecast = forecast_days[i]
                current_flood_forecast = {}

                # Evaluate pre activation condition
                current_flood_forecast = \
                    self._evaluate_flood_forecast_pre_activation_candidate(
                        current_flood_forecast, forecast, i, info, today)

                # If we don't have pre-activation candidate, skip to next day
                if not current_flood_forecast:
                    continue

                # Activation evaluation should be considered if the event
                # is a pre-activation candidate
                # Other than that, we don't have to evaluate it.
                # Now evaluate activation condition
                current_flood_forecast = \
                    self._evaluate_flood_forecast_activation_candidate(
                        current_flood_forecast, forecast, i, info, today)

                # current forecast now is best guess/candidate
                # of flood forecast
                if current_flood_forecast:
                    flood_forecast_events.append(current_flood_forecast)

        # We now have flood forecast event candidate
        # We push it to DB so the impact level can be calculated
        if self.use_plpy:
            created_ids = self.push_flood_forecast_event_plpy(flood_forecast_events)
        else:
            created_ids = self.push_flood_forecast_event_postgrest(flood_forecast_events)

        # patch id into the objects
        for i in range(len(flood_forecast_events)):
            flood_event_id = created_ids[i]
            flood_event = flood_forecast_events[i]
            flood_event['id'] = flood_event_id

        # store candidates data
        self.flood_forecast_events = flood_forecast_events

    def fetch_impacted_village(self, flood_event_id, impact_limit):
        query_param = self.impacted_village_query_filter.format(
            flood_event_id=flood_event_id,
            impact_limit=impact_limit)
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=query_param)
        response = requests.get(url)
        return response.json()

    def find_region_trigger_status(self, region, flood_event_id):
        query_param = self.region_trigger_status_query_filter.format(
            region=region,
            flood_event_id=flood_event_id)
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=query_param)
        response = requests.get(url)
        return response.json()

    def find_village_trigger_status(self, flood_event_id):
        return self.find_region_trigger_status('village', flood_event_id)

    def find_sub_district_trigger_status(self, flood_event_id):
        return self.find_region_trigger_status('sub_district', flood_event_id)

    def find_district_trigger_status(self, flood_event_id):
        return self.find_region_trigger_status('district', flood_event_id)

    def push_region_trigger_status(self, region, trigger_status_array):
        endpoint = self.region_trigger_status_endpoint.format(
            region=region)
        url = '{postgrest_url}{endpoint}'.format(
            postgrest_url=self.postgrest_url,
            endpoint=endpoint)

        # The process needs to be idempotent
        # So delete existing status first
        query_param = self.region_trigger_status_delete_query_param
        if not trigger_status_array:
            return
        flood_event_id = trigger_status_array[0]['flood_event_id']
        delete_url = url + query_param.format(flood_event_id=flood_event_id)
        requests.delete(delete_url)

        headers = {
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
        }
        # Bulk inserts
        json_string = json.dumps(trigger_status_array)
        response = requests.post(
            url,
            data=json_string,
            headers=headers)
        # Get the returned ids
        return response.json()

    def push_village_trigger_status(self, trigger_status_array):
        return self.push_region_trigger_status('village', trigger_status_array)

    def push_sub_district_trigger_status(self, trigger_status_array):
        return self.push_region_trigger_status('sub_district', trigger_status_array)

    def push_district_trigger_status(self, trigger_status_array):
        return self.push_region_trigger_status('district', trigger_status_array)

    def fetch_parent_administrative_mapping(self, parent_region, child_region, child_ids):
        json_array = '({})'.format(','.join([str(c) for c in child_ids]))
        query_param = self.parent_administrative_mapping.format(
            parent_region=parent_region,
            child_region=child_region,
            child_ids=json_array)
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=query_param)
        response = requests.get(url)
        mapping = response.json()

        # reverse the mapping as hash
        admin_hash = {}
        for m in mapping:
            child_id = m['{}_id'.format(child_region)]
            parent_id = m['{}_id'.format(parent_region)]
            admin_hash[child_id] = parent_id
        return admin_hash

    def fetch_sub_district_mapping(self, child_ids):
        return self.fetch_parent_administrative_mapping('sub_district', 'village', child_ids)

    def fetch_district_mapping(self, child_ids):
        return self.fetch_parent_administrative_mapping('district', 'sub_district', child_ids)

    def update_flood_event_forecast(self, flood_event):
        url = '{postgrest_url}{query_param}'.format(
            postgrest_url=self.postgrest_url,
            query_param=self.flood_event_insert_endpoint)
        headers = {
            'Content-Type': 'application/json',
            'Prefer': 'return=representation'
        }
        # Filter only the needed column to patch
        patch_data = {
            'trigger_status': flood_event['trigger_status'],
            'progress': flood_event['progress']
        }
        json_string = json.dumps(patch_data)

        # Perform update
        response = requests.patch(
            url + '?id=eq.{id}'.format(id=flood_event['id']),
            data=json_string,
            headers=headers)
        # Get the returned ids
        updated = response.json()

        return updated

    def evaluate_trigger_status(self):
        today = self.api.time or datetime.today().replace(
            hour=0, minute=0, second=0, microsecond=0)

        # Evaluate trigger status by considering impact level
        # At this point, impact data should already been calculated in the DB
        for flood_forecast in self.flood_forecast_events:

            # Evaluate pre activation criteria
            # Find impact data:
            villages_data = self.fetch_impacted_village(
                flood_forecast['id'], self.pre_activation_impact_limit)
            # Update each municipality trigger status
            # All villages that exceed impact limit means it is a
            # pre activation candidate

            if not villages_data:
                # Skip if impact tolerated
                flood_forecast['trigger_status'] = GloFASForecast.TRIGGER_STATUS_NO_ACTIVATION
                flood_forecast['progress'] = GloFASForecast.PROGRESS_DONE

                # Update flood_forecast information
                self.update_flood_event_forecast(flood_forecast)
                continue

            # Create village trigger status mapping
            village_trigger_status =[
                {
                    'flood_event_id': flood_forecast['id'],
                    'village_id': v['village_id'],
                    'trigger_status': GloFASForecast.TRIGGER_STATUS_PRE_ACTIVATION
                } for v in villages_data
            ]

            # Evaluate activation criteria
            # Check previous forecast activation
            forecast_date = flood_forecast['forecast_date']
            acquisition_date = today - timedelta(days=1)
            if self.use_plpy:
                flood_event = self.find_previous_flood_forecast_plpy(
                    forecast_date,
                    acquisition_date,
                    flood_forecast['source'])
            else:
                flood_event = self.find_previous_flood_forecast_postgrest(
                    forecast_date,
                    acquisition_date,
                    flood_forecast['source'])

            if flood_event:
                # We have previous forecast
                # Check if previous forecast is in pre activation stage
                previous_village_trigger_status = self.find_village_trigger_status(
                    flood_event['id'])
                # Create hash
                prev_village_hash = {}
                for village_state in previous_village_trigger_status:
                    status = village_state['trigger_status']
                    if status == GloFASForecast.TRIGGER_STATUS_PRE_ACTIVATION or status == GloFASForecast.TRIGGER_STATUS_ACTIVATION:
                        prev_village_hash[village_state['village_id']] =  village_state['trigger_status']

                # Evaluate which village exceed activation impact limit
                activation_candidate_village_data = self.fetch_impacted_village(
                    flood_forecast['id'], self.activation_impact_limit)

                activation_candidate_village_data = [v['village_id'] for v in activation_candidate_village_data]

                # Update trigger_status
                for village_state in village_trigger_status:
                    village_id = village_state['village_id']
                    # If it satisfy activation criteria, activate
                    if village_id in prev_village_hash and village_id in activation_candidate_village_data:
                        village_state['trigger_status'] = GloFASForecast.TRIGGER_STATUS_ACTIVATION

            # Insert to DB
            self.push_village_trigger_status(village_trigger_status)
            # Determine sub districts status
            sub_district_hash = {}
            # Fetch sub district mapping
            village_ids = [v['village_id'] for v in village_trigger_status]
            sub_district_mapping = self.fetch_sub_district_mapping(village_ids)

            for village_state in village_trigger_status:
                sub_district = sub_district_mapping[village_state['village_id']]
                status = village_state['trigger_status']
                try:
                    sub_district_hash[sub_district] = status if status > sub_district_hash[sub_district] else sub_district_hash[sub_district]
                except KeyError:
                    sub_district_hash[sub_district] = status

            # Reformat to array
            sub_district_trigger_status = []
            for key, value in sub_district_hash.items():
                sub_district_trigger_status.append({
                    'sub_district_id': key,
                    'flood_event_id': flood_forecast['id'],
                    'trigger_status': value
                })
            self.push_sub_district_trigger_status(sub_district_trigger_status)

            # Determine district status
            district_hash = {}
            # Fetch district mapping
            sub_district_ids = [s['sub_district_id'] for s in sub_district_trigger_status]
            district_mapping = self.fetch_district_mapping(sub_district_ids)

            for sub_district_state in sub_district_trigger_status:
                district = district_mapping[sub_district_state['sub_district_id']]
                status = sub_district_state['trigger_status']
                try:
                    district_hash[district] = status if status > district_hash[district] else district_hash[district]
                except KeyError:
                    district_hash[district] = status

            # Reformat to array
            district_trigger_status = []
            for key, value in district_hash.items():
                district_trigger_status.append({
                    'district_id': key,
                    'flood_event_id': flood_forecast['id'],
                    'trigger_status': value
                })
            self.push_district_trigger_status(district_trigger_status)

            # Update trigger status of the forecast
            final_trigger_status = GloFASForecast.TRIGGER_STATUS_PRE_ACTIVATION
            for district_state in district_trigger_status:
                status = district_state['trigger_status']
                final_trigger_status = status if status > final_trigger_status else final_trigger_status

            flood_forecast['trigger_status'] = final_trigger_status
            flood_forecast['progress'] = GloFASForecast.PROGRESS_DONE

            # Update flood_forecast information
            self.update_flood_event_forecast(flood_forecast)

    def run(self):
        self.fetch_forecast()
        self.process_forecast()
        self.evaluate_trigger_status()
    
    
    
job = GloFASForecast()
job.run()

return 'OK'
$_$;


--
-- Name: kartoza_fba_generate_excel_all_flood_events(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_fba_generate_excel_all_flood_events() RETURNS character varying
    LANGUAGE plpython3u
    AS $_$   
   res = plpy.execute("SELECT id from hazard_event")
   
   for flood_event in res:
     plan = plpy.prepare("SELECT * from kartoza_fba_generate_excel_report_for_flood(($1))", ["integer"])
     plpy.execute(plan, [flood_event['id']])
   return "OK"
$_$;


--
-- Name: kartoza_fba_generate_excel_report_for_flood(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_fba_generate_excel_report_for_flood(flood_event_id integer) RETURNS character varying
    LANGUAGE plpython3u
    AS $_$
    import io
    import sys

    plpy.execute("select * from satisfy_dependency('xlsxwriter')")
    plpy.execute("select * from satisfy_dependency('openpyxl')")

    from smartexcel.smart_excel import SmartExcel
    from smartexcel.fbf.data_model import FbfFloodData
    from smartexcel.fbf.definition import FBF_DEFINITION

    excel = SmartExcel(
        output=io.BytesIO(),
        definition=FBF_DEFINITION,
        data=FbfFloodData(
            flood_event_id=flood_event_id,
            pl_python_env=True
        )
    )

    excel.dump()
    
    plan = plpy.prepare("UPDATE spreadsheet_reports SET spreadsheet = ($1) where flood_event_id = ($2)", ["bytea", "integer"])
    plpy.execute(plan, [excel.output.getvalue(), flood_event_id])

    return "OK"
$_$;


--
-- Name: kartoza_generate_excel_report_for_flood(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_generate_excel_report_for_flood() RETURNS trigger
    LANGUAGE plpython3u
    AS $_$
    flood_event = TD["new"]["flood_event_id"]
    import io
    import sys
    plpy.execute("select * from satisfy_dependency('xlsxwriter')")
    plpy.execute("select * from satisfy_dependency('openpyxl')")
    from smartexcel.smart_excel import SmartExcel
    from smartexcel.fbf.data_model import FbfFloodData
    from smartexcel.fbf.definition import FBF_DEFINITION
    excel = SmartExcel(
        output=io.BytesIO(),
        definition=FBF_DEFINITION,
        data=FbfFloodData(
            flood_event_id=flood_event,
            pl_python_env=True
        )
    )
    excel.dump()
    plan = plpy.prepare("UPDATE spreadsheet_reports SET spreadsheet = ($1) where flood_event_id  = ($2)", ["bytea", "integer"])
    plpy.execute(plan, [excel.output.getvalue(), flood_event])
$_$;


--
-- Name: kartoza_populate_spreadsheet_table(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_populate_spreadsheet_table() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    insert into spreadsheet_reports (flood_event_id)
    values (NEW.id);
    RETURN NEW;
  END
  $$;


--
-- Name: kartoza_refresh_flood_district_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_district_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_district_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flood_event_buildings_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_event_buildings_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_flood_event_buildings WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flood_event_roads_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_event_roads_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_flood_event_roads WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flood_non_flooded_building_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_non_flooded_building_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_non_flooded_building_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flood_sub_event_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_sub_event_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_sub_district_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flood_village_event_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flood_village_event_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_village_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flooded_building_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flooded_building_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flooded_building_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_flooded_roads_summary_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_flooded_roads_summary_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_flooded_roads_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_non_flooded_roads_summary_mv(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_non_flooded_roads_summary_mv() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_non_flooded_roads_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_road_district_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_road_district_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_road_district_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_road_sub_district_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_road_sub_district_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_road_sub_district_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_refresh_road_village_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_refresh_road_village_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
  BEGIN
    REFRESH MATERIALIZED VIEW  mv_flood_event_road_village_summary WITH DATA ;
    RETURN NULL;
  END
  $$;


--
-- Name: kartoza_road_type_mapping(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_road_type_mapping() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    SELECT
    CASE
           WHEN new."type" ILIKE 'motorway' OR new."type" ILIKE 'highway' or new."type" ILIKE 'trunk'
               then 'Motorway or highway'
           WHEN new."type" ILIKE 'motorway_link' then 'Motorway link'
           WHEN new."type" ILIKE 'primary' then 'Primary road'
           WHEN new."type" ILIKE 'primary_link' then 'Primary link'
           WHEN new."type" ILIKE 'tertiary' then 'Tertiary'
           WHEN new."type" ILIKE 'tertiary_link' then 'Tertiary link'
           WHEN new."type" ILIKE 'secondary' then 'Secondary'
           WHEN new."type" ILIKE 'secondary_link' then 'Secondary link'
           WHEN new."type" ILIKE 'living_street' OR new."type" ILIKE 'residential' OR new."type" ILIKE 'yes'
                    OR new."type" ILIKE 'road' OR new."type" ILIKE 'unclassified' OR new."type" ILIKE 'service'
           OR new."type" ILIKE '' OR new."type" IS NULL then 'Road, residential, living street, etc.'
           WHEN new."type" ILIKE 'track' then 'Track'
           WHEN new."type" ILIKE 'cycleway' OR new."type" ILIKE 'footpath' OR new."type" ILIKE 'pedestrian'
                    OR new."type" ILIKE 'footway' OR new."type" ILIKE 'path' then 'Cycleway, footpath, etc.'
        END
    INTO new.road_type
    FROM osm_roads
    ;
  RETURN NEW;
  END
  $$;


--
-- Name: kartoza_test(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.kartoza_test(flood_event_id integer) RETURNS character varying
    LANGUAGE plpython3u
    AS $_$
   import io
   plpy.execute("select * from satisfy_dependency('xlsxwriter')")
   plpy.execute("select * from satisfy_dependency('openpyxl')")

   from smartexcel.smart_excel import SmartExcel
   from smartexcel.fbf.data_model import FbfFloodData
   from smartexcel.fbf.definition import FBF_DEFINITION

   excel = SmartExcel(
       output=io.BytesIO(),
       definition=FBF_DEFINITION,
       data=FbfFloodData(
           flood_event_id=flood_event_id,
           pl_python_env=True
       )
   )
   excel.dump()

   plan = plpy.prepare("UPDATE spreadsheet_reports SET spreadsheet = ($1) where id = ($2)", ["bytea", "integer"])
   plpy.execute(plan, [excel.output.getvalue(), flood_event_id])

   return "OK"
$_$;




-- Name: satisfy_dependency(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.satisfy_dependency(package character varying) RETURNS character varying
    LANGUAGE plpython3u
    AS $$
import subprocess
import importlib

try:
  importlib.import_module(package)
except ModuleNotFoundError:
  subprocess.check_call(["pip3", "install", package])
return 'OK'

$$;


--
-- Name: save_excel_as_blob(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.save_excel_as_blob() RETURNS character varying
    LANGUAGE plpython3u
    AS $_$
  import sys
  sys.path.insert(0, '/usr/local/lib/python3.7/dist-packages')
  import xlsxwriter
  sys.path.insert(0, '/usr/local/lib/python3.7/dist-packages/SmartExcel/smartexcel')
  return sys.version_info
  # from smartexcel import smart_excel
  import io
  
  ouput = io.BytesIO()
  workbook = xlsxwriter.Workbook('hello.xlsx')
  worksheet = workbook.add_worksheet()
  worksheet.write('A1', 'Hello world')
  workbook.close()
  # plan = plpy.prepare("UPDATE flood_event SET output = ($1)", ["bytea"])
  # plpy.execute(plan, [ouput])
  
  return ouput
  
$_$;



--
-- Name: test_falcon(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.test_falcon(package character varying) RETURNS character varying
    LANGUAGE plpython3u
    AS $$
import subprocess
subprocess.check_call(["pip3", "uninstall", "-y", "xlsxwriter"])
import xlsxwriter
workbook = xlsxwriter.Workbook('Expenses01.xlsx')

$$;



SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: building_type_class; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.building_type_class (
    id integer NOT NULL,
    building_class character varying(100)
);


--
-- Name: building_type_class_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.building_type_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: building_type_class_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.building_type_class_id_seq OWNED BY public.building_type_class.id;


--
-- Name: clip; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.clip (
    ogc_fid integer NOT NULL,
    id numeric(10,0),
    width numeric(21,6),
    height numeric(21,6),
    area numeric(21,6),
    perimeter numeric(21,6),
    geom public.geometry(MultiPolygon,4326)
);


--
-- Name: clip_ogc_fid_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.clip_ogc_fid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: clip_ogc_fid_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.clip_ogc_fid_seq OWNED BY public.clip.ogc_fid;


--
-- Name: hazard_class; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_class (
    id integer NOT NULL,
    min_m double precision,
    max_m double precision,
    label character varying(255)
);


--
-- Name: depth_class_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.depth_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: depth_class_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.depth_class_id_seq OWNED BY public.hazard_class.id;


--
-- Name: dev_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.dev_reports (
    output bytea
);


--
-- Name: district; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.district (
    id integer NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    prov_code double precision,
    dc_code double precision NOT NULL,
    name character varying(254)
);


--
-- Name: district_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.district_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: district_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.district_id_seq OWNED BY public.district.id;


--
-- Name: district_trigger_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.district_trigger_status (
    id integer NOT NULL,
    district_id double precision,
    trigger_status integer,
    flood_event_id integer
);


--
-- Name: district_trigger_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.district_trigger_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: district_trigger_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.district_trigger_status_id_seq OWNED BY public.district_trigger_status.id;


--
-- Name: fb_gavin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.fb_gavin (
    flood_event_id integer,
    district_id double precision,
    sub_district_id numeric,
    village_id double precision,
    building_type character varying(100),
    district_count bigint,
    sub_district_count bigint,
    village_count bigint,
    building_type_count bigint
);


--
-- Name: flood_event_buildings_gavin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.flood_event_buildings_gavin (
    flood_event_id integer,
    district_id double precision,
    sub_district_id numeric,
    village_id double precision,
    building_type character varying(100),
    buildings_in_district bigint,
    buildings_in_sub_district bigint,
    buildings_in_village bigint,
    buildings_of_type_in_village bigint,
    flooded_buildings_in_district bigint,
    flooded_buildings_in_sub_district bigint,
    flooded_buildings_in_village bigint,
    flooded_buildings_of_type_in_village bigint
);


--
-- Name: hazard_event_buildings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_event_buildings (
    id integer NOT NULL,
    flood_event_id integer,
    building_id integer,
    depth_class_id integer
);


--
-- Name: flood_event_buildings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flood_event_buildings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flood_event_buildings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flood_event_buildings_id_seq OWNED BY public.hazard_event_buildings.id;


--
-- Name: hazard_map; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_map (
    id integer NOT NULL,
    notes character varying(255),
    measuring_station_id integer,
    place_name character varying(255),
    return_period integer
);


--
-- Name: flood_map_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flood_map_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flood_map_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flood_map_id_seq OWNED BY public.hazard_map.id;


--
-- Name: hazard_area; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_area (
    id integer NOT NULL,
    depth_class integer,
    geometry public.geometry(MultiPolygon,4326)
);


--
-- Name: flooded_area_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flooded_area_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flooded_area_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flooded_area_id_seq OWNED BY public.hazard_area.id;


--
-- Name: hazard_areas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_areas (
    id integer NOT NULL,
    flood_map_id integer,
    flooded_area_id integer
);


--
-- Name: flooded_areas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.flooded_areas_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: flooded_areas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.flooded_areas_id_seq OWNED BY public.hazard_areas.id;


--
-- Name: hazard_event; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_event (
    id integer NOT NULL,
    flood_map_id integer,
    acquisition_date timestamp without time zone DEFAULT now() NOT NULL,
    forecast_date timestamp without time zone,
    source text,
    notes text,
    link text,
    trigger_status integer,
    progress integer,
    hazard_type_id integer
);


--
-- Name: forecast_flood_event_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.forecast_flood_event_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: forecast_flood_event_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.forecast_flood_event_id_seq OWNED BY public.hazard_event.id;


--
-- Name: hazard; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard (
    id integer NOT NULL,
    geometry public.geometry(MultiPolygon,4326),
    name character varying(80),
    source character varying(255),
    reporting_date_time timestamp without time zone,
    forecast_date_time timestamp without time zone,
    station character varying(255)
);


--
-- Name: hazard_type; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.hazard_type (
    id integer NOT NULL,
    name text
);


--
-- Name: hazard_type_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.hazard_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: hazard_type_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.hazard_type_id_seq OWNED BY public.hazard_type.id;


--
-- Name: layer_styles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.layer_styles (
    id integer NOT NULL,
    f_table_catalog character varying,
    f_table_schema character varying,
    f_table_name character varying,
    f_geometry_column character varying,
    stylename character varying(30),
    styleqml xml,
    stylesld xml,
    useasdefault boolean,
    description text,
    owner character varying(30),
    ui xml,
    update_time timestamp without time zone DEFAULT now()
);


--
-- Name: layer_styles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.layer_styles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: layer_styles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.layer_styles_id_seq OWNED BY public.layer_styles.id;


--
-- Name: sub_district; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_district (
    id integer NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    prov_code smallint,
    dc_code smallint,
    name character varying(255),
    sub_dc_code numeric NOT NULL
);


--
-- Name: village; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.village (
    id integer NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    prov_code double precision,
    dc_code double precision,
    sub_dc_code double precision,
    village_code double precision NOT NULL,
    name character varying(254)
);


--
-- Name: mv_administrative_mapping; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_administrative_mapping AS
 SELECT district.dc_code AS district_id,
    district.name AS district_name,
    sub_district.sub_dc_code AS sub_district_id,
    sub_district.name AS sub_district_name,
    village.village_code AS village_id,
    village.name AS village_name
   FROM ((public.district
     JOIN public.sub_district ON ((district.dc_code = (sub_district.dc_code)::double precision)))
     JOIN public.village ON (((sub_district.sub_dc_code)::double precision = village.sub_dc_code)))
  WITH NO DATA;


--
-- Name: osm_buildings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_buildings (
    id integer NOT NULL,
    osm_id bigint NOT NULL,
    name character varying,
    use character varying,
    religion character varying,
    leisure character varying,
    height integer,
    "building:levels" character varying,
    "building:height" integer,
    "building:min_level" integer,
    "roof:direction" character varying,
    "roof:levels" integer,
    "roof:shape" character varying,
    surface character varying,
    "roof:orientation" character varying,
    "roof:height" integer,
    "roof:material" character varying,
    "building:material" character varying,
    type character varying,
    amenity character varying,
    landuse character varying,
    geometry public.geometry(Geometry,4326),
    building_type character varying(100),
    building_area numeric,
    building_type_score numeric,
    building_road_length numeric,
    building_material_score numeric,
    building_area_score numeric,
    building_road_density_score numeric,
    total_vulnerability numeric,
    building_road_density integer,
    building_id integer,
    village_id double precision,
    sub_district_id numeric,
    district_id double precision,
    changeset_id integer,
    changeset_version integer,
    changeset_timestamp timestamp without time zone,
    changeset_user character varying
);


--
-- Name: mv_flood_event_buildings; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_buildings AS
 WITH intersections AS (
         SELECT a_1.geometry,
            d.id AS flood_event_id,
            a_1.depth_class
           FROM (((public.hazard_area a_1
             JOIN public.hazard_areas b_1 ON ((a_1.id = b_1.flooded_area_id)))
             JOIN public.hazard_map c ON ((c.id = b_1.flood_map_id)))
             JOIN public.hazard_event d ON ((d.flood_map_id = c.id)))
        )
 SELECT row_number() OVER () AS id,
    b.osm_id AS building_id,
    a.flood_event_id,
    a.depth_class,
    b.district_id,
    b.sub_district_id,
    b.village_id,
    b.building_type,
    b.total_vulnerability,
    b.geometry
   FROM (intersections a
     JOIN public.osm_buildings b ON (public.st_intersects(a.geometry, b.geometry)))
  WHERE (b.building_area < (7000)::numeric)
  WITH NO DATA;


--
-- Name: mv_flooded_building_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flooded_building_summary AS
 SELECT DISTINCT a.flood_event_id,
    a.district_id,
    a.sub_district_id,
    a.village_id,
    a.building_type,
    count(*) OVER (PARTITION BY a.flood_event_id, a.district_id) AS district_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.sub_district_id) AS sub_district_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.village_id) AS village_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.district_id, a.sub_district_id, a.village_id, a.building_type) AS building_type_count,
    sum(a.total_vulnerability) OVER (PARTITION BY a.flood_event_id, a.district_id, a.sub_district_id, a.village_id, a.building_type) AS total_vulnerability_score
   FROM ( SELECT DISTINCT mv_flood_event_buildings.flood_event_id,
            mv_flood_event_buildings.district_id,
            mv_flood_event_buildings.sub_district_id,
            mv_flood_event_buildings.village_id,
            mv_flood_event_buildings.building_id,
            mv_flood_event_buildings.building_type,
            mv_flood_event_buildings.total_vulnerability,
            max(mv_flood_event_buildings.depth_class) AS depth_class
           FROM public.mv_flood_event_buildings
          GROUP BY mv_flood_event_buildings.flood_event_id, mv_flood_event_buildings.district_id, mv_flood_event_buildings.sub_district_id, mv_flood_event_buildings.village_id, mv_flood_event_buildings.building_id, mv_flood_event_buildings.building_type, mv_flood_event_buildings.total_vulnerability) a
  WITH NO DATA;


--
-- Name: mv_non_flooded_building_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_non_flooded_building_summary AS
 SELECT DISTINCT osm_buildings.district_id,
    osm_buildings.sub_district_id,
    osm_buildings.village_id,
    osm_buildings.building_type,
    count(*) OVER (PARTITION BY osm_buildings.district_id) AS district_count,
    count(*) OVER (PARTITION BY osm_buildings.sub_district_id) AS sub_district_count,
    count(*) OVER (PARTITION BY osm_buildings.village_id) AS village_count,
    count(*) OVER (PARTITION BY osm_buildings.village_id, osm_buildings.building_type) AS building_type_count
   FROM public.osm_buildings
  ORDER BY osm_buildings.district_id, osm_buildings.sub_district_id, osm_buildings.village_id, osm_buildings.building_type
  WITH NO DATA;


--
-- Name: mv_flood_event_district_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_district_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            sum(b_1.building_type_count) AS building_count,
            sum(b_1.residential_building_count) AS residential_building_count,
            sum(b_1.clinic_dr_building_count) AS clinic_dr_building_count,
            sum(b_1.fire_station_building_count) AS fire_station_building_count,
            sum(b_1.school_building_count) AS school_building_count,
            sum(b_1.university_building_count) AS university_building_count,
            sum(b_1.government_building_count) AS government_building_count,
            sum(b_1.hospital_building_count) AS hospital_building_count,
            sum(b_1.police_station_building_count) AS police_station_building_count,
            sum(b_1.supermarket_building_count) AS supermarket_building_count,
            sum(b_1.sports_facility_building_count) AS sports_facility_building_count
           FROM ( SELECT DISTINCT mv_non_flooded_building_summary.district_id,
                    mv_non_flooded_building_summary.sub_district_id,
                    mv_non_flooded_building_summary.village_id,
                    mv_non_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count
                   FROM public.mv_non_flooded_building_summary
                  WHERE ((mv_non_flooded_building_summary.district_id IS NOT NULL) AND (mv_non_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_building_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            sum(a.building_type_count) AS flooded_building_count,
            sum(a.residential_building_count) AS residential_flooded_building_count,
            sum(a.clinic_dr_building_count) AS clinic_dr_flooded_building_count,
            sum(a.fire_station_building_count) AS fire_station_flooded_building_count,
            sum(a.school_building_count) AS school_flooded_building_count,
            sum(a.university_building_count) AS university_flooded_building_count,
            sum(a.government_building_count) AS government_flooded_building_count,
            sum(a.hospital_building_count) AS hospital_flooded_building_count,
            sum(a.police_station_building_count) AS police_station_flooded_building_count,
            sum(a.supermarket_building_count) AS supermarket_flooded_building_count,
            sum(a.sports_facility_building_count) AS sports_facility_flooded_building_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_building_summary.flood_event_id,
                    mv_flooded_building_summary.district_id,
                    mv_flooded_building_summary.sub_district_id,
                    mv_flooded_building_summary.village_id,
                    mv_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count,
                    mv_flooded_building_summary.total_vulnerability_score
                   FROM public.mv_flooded_building_summary
                  WHERE ((mv_flooded_building_summary.district_id IS NOT NULL) AND (mv_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_flooded_building_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT a.flood_event_id,
            a.district_id,
            district.name,
            a.flooded_building_count,
            b_1.building_count,
            b_1.residential_building_count,
            b_1.clinic_dr_building_count,
            b_1.fire_station_building_count,
            b_1.school_building_count,
            b_1.university_building_count,
            b_1.government_building_count,
            b_1.hospital_building_count,
            b_1.police_station_building_count,
            b_1.supermarket_building_count,
            b_1.sports_facility_building_count,
            a.residential_flooded_building_count,
            a.clinic_dr_flooded_building_count,
            a.fire_station_flooded_building_count,
            a.school_flooded_building_count,
            a.university_flooded_building_count,
            a.government_flooded_building_count,
            a.hospital_flooded_building_count,
            a.police_station_flooded_building_count,
            a.supermarket_flooded_building_count,
            a.sports_facility_flooded_building_count,
            a.total_vulnerability_score
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON ((a.district_id = b_1.district_id)))
             JOIN public.district ON ((district.dc_code = a.district_id)))
        )
 SELECT flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.name,
    flooded_aggregate_count.building_count,
    flooded_aggregate_count.flooded_building_count,
    flooded_aggregate_count.total_vulnerability_score,
    flooded_aggregate_count.residential_flooded_building_count,
    flooded_aggregate_count.clinic_dr_flooded_building_count,
    flooded_aggregate_count.fire_station_flooded_building_count,
    flooded_aggregate_count.school_flooded_building_count,
    flooded_aggregate_count.university_flooded_building_count,
    flooded_aggregate_count.government_flooded_building_count,
    flooded_aggregate_count.hospital_flooded_building_count,
    flooded_aggregate_count.police_station_flooded_building_count,
    flooded_aggregate_count.supermarket_flooded_building_count,
    flooded_aggregate_count.sports_facility_flooded_building_count,
    flooded_aggregate_count.residential_building_count,
    flooded_aggregate_count.clinic_dr_building_count,
    flooded_aggregate_count.fire_station_building_count,
    flooded_aggregate_count.school_building_count,
    flooded_aggregate_count.university_building_count,
    flooded_aggregate_count.government_building_count,
    flooded_aggregate_count.hospital_building_count,
    flooded_aggregate_count.police_station_building_count,
    flooded_aggregate_count.supermarket_building_count,
    flooded_aggregate_count.sports_facility_building_count,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.district_trigger_status b ON (((b.district_id = flooded_aggregate_count.district_id) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: osm_roads; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_roads (
    id integer NOT NULL,
    osm_id bigint NOT NULL,
    type character varying,
    name character varying,
    class character varying,
    geometry public.geometry(LineString,4326),
    road_type character varying(50),
    roads_id integer,
    changeset_id integer,
    changeset_version integer,
    changeset_timestamp timestamp without time zone,
    changeset_user character varying,
    village_id double precision,
    district_id double precision,
    sub_district_id numeric,
    road_type_score numeric
);


--
-- Name: mv_flood_event_roads; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_roads AS
 WITH intersections AS (
         SELECT a_1.geometry,
            d.id AS flood_event_id,
            a_1.depth_class
           FROM (((public.hazard_area a_1
             JOIN public.hazard_areas b_1 ON ((a_1.id = b_1.flooded_area_id)))
             JOIN public.hazard_map c ON ((c.id = b_1.flood_map_id)))
             JOIN public.hazard_event d ON ((d.flood_map_id = c.id)))
        )
 SELECT row_number() OVER () AS id,
    b.osm_id AS road_id,
    a.flood_event_id,
    a.depth_class,
    b.district_id,
    b.sub_district_id,
    b.village_id,
    b.road_type,
    b.road_type_score AS total_vulnerability,
    b.geometry
   FROM (intersections a
     JOIN public.osm_roads b ON (public.st_intersects(a.geometry, b.geometry)))
  WITH NO DATA;


--
-- Name: mv_flooded_roads_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flooded_roads_summary AS
 SELECT DISTINCT a.flood_event_id,
    a.district_id,
    a.sub_district_id,
    a.village_id,
    a.road_type,
    count(*) OVER (PARTITION BY a.flood_event_id, a.district_id) AS district_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.sub_district_id) AS sub_district_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.village_id) AS village_count,
    count(*) OVER (PARTITION BY a.flood_event_id, a.district_id, a.sub_district_id, a.village_id, a.road_type) AS road_type_count,
    sum(a.total_vulnerability) OVER (PARTITION BY a.flood_event_id, a.district_id, a.sub_district_id, a.village_id, a.road_type) AS total_vulnerability_score
   FROM ( SELECT DISTINCT mv_flood_event_roads.flood_event_id,
            mv_flood_event_roads.district_id,
            mv_flood_event_roads.sub_district_id,
            mv_flood_event_roads.village_id,
            mv_flood_event_roads.road_id,
            mv_flood_event_roads.road_type,
            mv_flood_event_roads.total_vulnerability,
            max(mv_flood_event_roads.depth_class) AS depth_class
           FROM public.mv_flood_event_roads
          GROUP BY mv_flood_event_roads.flood_event_id, mv_flood_event_roads.district_id, mv_flood_event_roads.sub_district_id, mv_flood_event_roads.village_id, mv_flood_event_roads.road_id, mv_flood_event_roads.road_type, mv_flood_event_roads.total_vulnerability) a
  WITH NO DATA;


--
-- Name: mv_non_flooded_roads_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_non_flooded_roads_summary AS
 SELECT DISTINCT osm_roads.district_id,
    osm_roads.sub_district_id,
    osm_roads.village_id,
    osm_roads.road_type,
    count(*) OVER (PARTITION BY osm_roads.district_id) AS district_count,
    count(*) OVER (PARTITION BY osm_roads.sub_district_id) AS sub_district_count,
    count(*) OVER (PARTITION BY osm_roads.village_id) AS village_count,
    count(*) OVER (PARTITION BY osm_roads.village_id, osm_roads.road_type) AS road_type_count
   FROM public.osm_roads
  ORDER BY osm_roads.district_id, osm_roads.sub_district_id, osm_roads.village_id, osm_roads.road_type
  WITH NO DATA;


--
-- Name: mv_flood_event_road_district_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_road_district_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            sum(b_1.road_type_count) AS road_count,
            sum(b_1.motorway_highway_road_count) AS motorway_highway_road_count,
            sum(b_1.tertiary_link_road_count) AS tertiary_link_road_count,
            sum(b_1.secondary_road_count) AS secondary_road_count,
            sum(b_1.secondary_link_road_count) AS secondary_link_road_count,
            sum(b_1.tertiary_road_count) AS tertiary_road_count,
            sum(b_1.primary_link_road_count) AS primary_link_road_count,
            sum(b_1.track_road_count) AS track_road_count,
            sum(b_1.primary_road_count) AS primary_road_count,
            sum(b_1.motorway_link_road_count) AS motorway_link_road_count,
            sum(b_1.residential_road_count) AS residential_road_count
           FROM ( SELECT DISTINCT mv_non_flooded_roads_summary.district_id,
                    mv_non_flooded_roads_summary.sub_district_id,
                    mv_non_flooded_roads_summary.village_id,
                    mv_non_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count
                   FROM public.mv_non_flooded_roads_summary
                  WHERE ((mv_non_flooded_roads_summary.district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            sum(a.road_type_count) AS flooded_flooded_road_count,
            sum(a.motorway_highway_road_count) AS motorway_highway_flooded_road_count,
            sum(a.tertiary_link_road_count) AS tertiary_link_flooded_road_count,
            sum(a.secondary_road_count) AS secondary_flooded_road_count,
            sum(a.secondary_link_road_count) AS secondary_link_flooded_road_count,
            sum(a.tertiary_road_count) AS tertiary_flooded_road_count,
            sum(a.primary_link_road_count) AS primary_link_flooded_road_count,
            sum(a.track_road_count) AS track_flooded_road_count,
            sum(a.primary_road_count) AS primary_flooded_road_count,
            sum(a.motorway_link_road_count) AS motorway_link_flooded_road_count,
            sum(a.residential_road_count) AS residential_flooded_road_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_roads_summary.flood_event_id,
                    mv_flooded_roads_summary.district_id,
                    mv_flooded_roads_summary.sub_district_id,
                    mv_flooded_roads_summary.village_id,
                    mv_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count,
                    mv_flooded_roads_summary.total_vulnerability_score
                   FROM public.mv_flooded_roads_summary
                  WHERE ((mv_flooded_roads_summary.district_id IS NOT NULL) AND (mv_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_flooded_roads_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT district.name,
            b_1.road_count,
            b_1.motorway_highway_road_count,
            b_1.tertiary_link_road_count,
            b_1.secondary_road_count,
            b_1.secondary_link_road_count,
            b_1.tertiary_road_count,
            b_1.primary_link_road_count,
            b_1.track_road_count,
            b_1.primary_road_count,
            b_1.motorway_link_road_count,
            b_1.residential_road_count,
            a.flood_event_id,
            a.district_id,
            a.flooded_flooded_road_count,
            a.motorway_highway_flooded_road_count,
            a.tertiary_link_flooded_road_count,
            a.secondary_flooded_road_count,
            a.secondary_link_flooded_road_count,
            a.tertiary_flooded_road_count,
            a.primary_link_flooded_road_count,
            a.track_flooded_road_count,
            a.primary_flooded_road_count,
            a.motorway_link_flooded_road_count,
            a.residential_flooded_road_count,
            a.total_vulnerability_score
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON ((a.district_id = b_1.district_id)))
             JOIN public.district ON ((district.dc_code = a.district_id)))
        )
 SELECT flooded_aggregate_count.name,
    flooded_aggregate_count.road_count,
    flooded_aggregate_count.motorway_highway_road_count,
    flooded_aggregate_count.tertiary_link_road_count,
    flooded_aggregate_count.secondary_road_count,
    flooded_aggregate_count.secondary_link_road_count,
    flooded_aggregate_count.tertiary_road_count,
    flooded_aggregate_count.primary_link_road_count,
    flooded_aggregate_count.track_road_count,
    flooded_aggregate_count.primary_road_count,
    flooded_aggregate_count.motorway_link_road_count,
    flooded_aggregate_count.residential_road_count,
    flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.flooded_flooded_road_count,
    flooded_aggregate_count.motorway_highway_flooded_road_count,
    flooded_aggregate_count.tertiary_link_flooded_road_count,
    flooded_aggregate_count.secondary_flooded_road_count,
    flooded_aggregate_count.secondary_link_flooded_road_count,
    flooded_aggregate_count.tertiary_flooded_road_count,
    flooded_aggregate_count.primary_link_flooded_road_count,
    flooded_aggregate_count.track_flooded_road_count,
    flooded_aggregate_count.primary_flooded_road_count,
    flooded_aggregate_count.motorway_link_flooded_road_count,
    flooded_aggregate_count.residential_flooded_road_count,
    flooded_aggregate_count.total_vulnerability_score,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.district_trigger_status b ON (((b.district_id = flooded_aggregate_count.district_id) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: sub_district_trigger_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sub_district_trigger_status (
    id integer NOT NULL,
    sub_district_id double precision,
    trigger_status integer,
    flood_event_id integer
);


--
-- Name: mv_flood_event_road_sub_district_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_road_sub_district_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            b_1.sub_district_id,
            sum(b_1.road_type_count) AS road_count,
            sum(b_1.motorway_highway_road_count) AS motorway_highway_road_count,
            sum(b_1.tertiary_link_road_count) AS tertiary_link_road_count,
            sum(b_1.secondary_road_count) AS secondary_road_count,
            sum(b_1.secondary_link_road_count) AS secondary_link_road_count,
            sum(b_1.tertiary_road_count) AS tertiary_road_count,
            sum(b_1.primary_link_road_count) AS primary_link_road_count,
            sum(b_1.track_road_count) AS track_road_count,
            sum(b_1.primary_road_count) AS primary_road_count,
            sum(b_1.motorway_link_road_count) AS motorway_link_road_count,
            sum(b_1.residential_road_count) AS residential_road_count
           FROM ( SELECT DISTINCT mv_non_flooded_roads_summary.district_id,
                    mv_non_flooded_roads_summary.sub_district_id,
                    mv_non_flooded_roads_summary.village_id,
                    mv_non_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count
                   FROM public.mv_non_flooded_roads_summary
                  WHERE ((mv_non_flooded_roads_summary.district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id, b_1.sub_district_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            sum(a.road_type_count) AS flooded_flooded_road_count,
            sum(a.motorway_highway_road_count) AS motorway_highway_flooded_road_count,
            sum(a.tertiary_link_road_count) AS tertiary_link_flooded_road_count,
            sum(a.secondary_road_count) AS secondary_flooded_road_count,
            sum(a.secondary_link_road_count) AS secondary_link_flooded_road_count,
            sum(a.tertiary_road_count) AS tertiary_flooded_road_count,
            sum(a.primary_link_road_count) AS primary_link_flooded_road_count,
            sum(a.track_road_count) AS track_flooded_road_count,
            sum(a.primary_road_count) AS primary_flooded_road_count,
            sum(a.motorway_link_road_count) AS motorway_link_flooded_road_count,
            sum(a.residential_road_count) AS residential_flooded_road_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_roads_summary.flood_event_id,
                    mv_flooded_roads_summary.district_id,
                    mv_flooded_roads_summary.sub_district_id,
                    mv_flooded_roads_summary.village_id,
                    mv_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count,
                    mv_flooded_roads_summary.total_vulnerability_score
                   FROM public.mv_flooded_roads_summary
                  WHERE ((mv_flooded_roads_summary.district_id IS NOT NULL) AND (mv_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_flooded_roads_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.sub_district_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            a.flooded_flooded_road_count,
            a.motorway_highway_flooded_road_count,
            a.tertiary_link_flooded_road_count,
            a.secondary_flooded_road_count,
            a.secondary_link_flooded_road_count,
            a.tertiary_flooded_road_count,
            a.primary_link_flooded_road_count,
            a.track_flooded_road_count,
            a.primary_flooded_road_count,
            a.motorway_link_flooded_road_count,
            a.residential_flooded_road_count,
            a.total_vulnerability_score,
            sub_district.name,
            b_1.road_count,
            b_1.motorway_highway_road_count,
            b_1.tertiary_link_road_count,
            b_1.secondary_road_count,
            b_1.secondary_link_road_count,
            b_1.tertiary_road_count,
            b_1.primary_link_road_count,
            b_1.track_road_count,
            b_1.primary_road_count,
            b_1.motorway_link_road_count,
            b_1.residential_road_count
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON (((a.district_id = b_1.district_id) AND (a.sub_district_id = b_1.sub_district_id))))
             JOIN public.sub_district ON ((sub_district.sub_dc_code = a.sub_district_id)))
        )
 SELECT flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.sub_district_id,
    flooded_aggregate_count.flooded_flooded_road_count,
    flooded_aggregate_count.motorway_highway_flooded_road_count,
    flooded_aggregate_count.tertiary_link_flooded_road_count,
    flooded_aggregate_count.secondary_flooded_road_count,
    flooded_aggregate_count.secondary_link_flooded_road_count,
    flooded_aggregate_count.tertiary_flooded_road_count,
    flooded_aggregate_count.primary_link_flooded_road_count,
    flooded_aggregate_count.track_flooded_road_count,
    flooded_aggregate_count.primary_flooded_road_count,
    flooded_aggregate_count.motorway_link_flooded_road_count,
    flooded_aggregate_count.residential_flooded_road_count,
    flooded_aggregate_count.total_vulnerability_score,
    flooded_aggregate_count.name,
    flooded_aggregate_count.road_count,
    flooded_aggregate_count.motorway_highway_road_count,
    flooded_aggregate_count.tertiary_link_road_count,
    flooded_aggregate_count.secondary_road_count,
    flooded_aggregate_count.secondary_link_road_count,
    flooded_aggregate_count.tertiary_road_count,
    flooded_aggregate_count.primary_link_road_count,
    flooded_aggregate_count.track_road_count,
    flooded_aggregate_count.primary_road_count,
    flooded_aggregate_count.motorway_link_road_count,
    flooded_aggregate_count.residential_road_count,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.sub_district_trigger_status b ON (((b.sub_district_id = (flooded_aggregate_count.sub_district_id)::double precision) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: mv_flood_event_road_village_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_road_village_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            b_1.sub_district_id,
            b_1.village_id,
            sum(b_1.road_type_count) AS road_count,
            sum(b_1.motorway_highway_road_count) AS motorway_highway_road_count,
            sum(b_1.tertiary_link_road_count) AS tertiary_link_road_count,
            sum(b_1.secondary_road_count) AS secondary_road_count,
            sum(b_1.secondary_link_road_count) AS secondary_link_road_count,
            sum(b_1.tertiary_road_count) AS tertiary_road_count,
            sum(b_1.primary_link_road_count) AS primary_link_road_count,
            sum(b_1.track_road_count) AS track_road_count,
            sum(b_1.primary_road_count) AS primary_road_count,
            sum(b_1.motorway_link_road_count) AS motorway_link_road_count,
            sum(b_1.residential_road_count) AS residential_road_count
           FROM ( SELECT DISTINCT mv_non_flooded_roads_summary.district_id,
                    mv_non_flooded_roads_summary.sub_district_id,
                    mv_non_flooded_roads_summary.village_id,
                    mv_non_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_non_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_non_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count
                   FROM public.mv_non_flooded_roads_summary
                  WHERE ((mv_non_flooded_roads_summary.district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_roads_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id, b_1.sub_district_id, b_1.village_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            a.village_id,
            sum(a.road_type_count) AS flooded_flooded_road_count,
            sum(a.motorway_highway_road_count) AS motorway_highway_flooded_road_count,
            sum(a.tertiary_link_road_count) AS tertiary_link_flooded_road_count,
            sum(a.secondary_road_count) AS secondary_flooded_road_count,
            sum(a.secondary_link_road_count) AS secondary_link_flooded_road_count,
            sum(a.tertiary_road_count) AS tertiary_flooded_road_count,
            sum(a.primary_link_road_count) AS primary_link_flooded_road_count,
            sum(a.track_road_count) AS track_flooded_road_count,
            sum(a.primary_road_count) AS primary_flooded_road_count,
            sum(a.motorway_link_road_count) AS motorway_link_flooded_road_count,
            sum(a.residential_road_count) AS residential_flooded_road_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_roads_summary.flood_event_id,
                    mv_flooded_roads_summary.district_id,
                    mv_flooded_roads_summary.sub_district_id,
                    mv_flooded_roads_summary.village_id,
                    mv_flooded_roads_summary.road_type_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway or highway'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_highway_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Secondary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS secondary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Tertiary'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS tertiary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Track'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS track_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Primary road'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS primary_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Motorway link'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS motorway_link_road_count,
                        CASE
                            WHEN ((mv_flooded_roads_summary.road_type)::text = 'Road, residential, living street, etc.'::text) THEN mv_flooded_roads_summary.road_type_count
                            ELSE (0)::bigint
                        END AS residential_road_count,
                    mv_flooded_roads_summary.total_vulnerability_score
                   FROM public.mv_flooded_roads_summary
                  WHERE ((mv_flooded_roads_summary.district_id IS NOT NULL) AND (mv_flooded_roads_summary.sub_district_id IS NOT NULL) AND (mv_flooded_roads_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.sub_district_id, a.village_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            a.village_id,
            a.flooded_flooded_road_count,
            a.motorway_highway_flooded_road_count,
            a.tertiary_link_flooded_road_count,
            a.secondary_flooded_road_count,
            a.secondary_link_flooded_road_count,
            a.tertiary_flooded_road_count,
            a.primary_link_flooded_road_count,
            a.track_flooded_road_count,
            a.primary_flooded_road_count,
            a.motorway_link_flooded_road_count,
            a.residential_flooded_road_count,
            a.total_vulnerability_score,
            sub_district.name,
            b_1.road_count,
            b_1.motorway_highway_road_count,
            b_1.tertiary_link_road_count,
            b_1.secondary_road_count,
            b_1.secondary_link_road_count,
            b_1.tertiary_road_count,
            b_1.primary_link_road_count,
            b_1.track_road_count,
            b_1.primary_road_count,
            b_1.motorway_link_road_count,
            b_1.residential_road_count
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON (((a.district_id = b_1.district_id) AND (a.sub_district_id = b_1.sub_district_id))))
             JOIN public.sub_district ON ((sub_district.sub_dc_code = a.sub_district_id)))
        )
 SELECT flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.sub_district_id,
    flooded_aggregate_count.village_id,
    flooded_aggregate_count.flooded_flooded_road_count,
    flooded_aggregate_count.motorway_highway_flooded_road_count,
    flooded_aggregate_count.tertiary_link_flooded_road_count,
    flooded_aggregate_count.secondary_flooded_road_count,
    flooded_aggregate_count.secondary_link_flooded_road_count,
    flooded_aggregate_count.tertiary_flooded_road_count,
    flooded_aggregate_count.primary_link_flooded_road_count,
    flooded_aggregate_count.track_flooded_road_count,
    flooded_aggregate_count.primary_flooded_road_count,
    flooded_aggregate_count.motorway_link_flooded_road_count,
    flooded_aggregate_count.residential_flooded_road_count,
    flooded_aggregate_count.total_vulnerability_score,
    flooded_aggregate_count.name,
    flooded_aggregate_count.road_count,
    flooded_aggregate_count.motorway_highway_road_count,
    flooded_aggregate_count.tertiary_link_road_count,
    flooded_aggregate_count.secondary_road_count,
    flooded_aggregate_count.secondary_link_road_count,
    flooded_aggregate_count.tertiary_road_count,
    flooded_aggregate_count.primary_link_road_count,
    flooded_aggregate_count.track_road_count,
    flooded_aggregate_count.primary_road_count,
    flooded_aggregate_count.motorway_link_road_count,
    flooded_aggregate_count.residential_road_count,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.sub_district_trigger_status b ON (((b.sub_district_id = (flooded_aggregate_count.sub_district_id)::double precision) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: mv_flood_event_sub_district_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_sub_district_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            b_1.sub_district_id,
            sum(b_1.building_type_count) AS building_count,
            sum(b_1.residential_building_count) AS residential_building_count,
            sum(b_1.clinic_dr_building_count) AS clinic_dr_building_count,
            sum(b_1.fire_station_building_count) AS fire_station_building_count,
            sum(b_1.school_building_count) AS school_building_count,
            sum(b_1.university_building_count) AS university_building_count,
            sum(b_1.government_building_count) AS government_building_count,
            sum(b_1.hospital_building_count) AS hospital_building_count,
            sum(b_1.police_station_building_count) AS police_station_building_count,
            sum(b_1.supermarket_building_count) AS supermarket_building_count,
            sum(b_1.sports_facility_building_count) AS sports_facility_building_count
           FROM ( SELECT DISTINCT mv_non_flooded_building_summary.district_id,
                    mv_non_flooded_building_summary.sub_district_id,
                    mv_non_flooded_building_summary.village_id,
                    mv_non_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count
                   FROM public.mv_non_flooded_building_summary
                  WHERE ((mv_non_flooded_building_summary.district_id IS NOT NULL) AND (mv_non_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_building_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id, b_1.sub_district_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            sum(a.building_type_count) AS flooded_building_count,
            sum(a.residential_building_count) AS residential_flooded_building_count,
            sum(a.clinic_dr_building_count) AS clinic_dr_flooded_building_count,
            sum(a.fire_station_building_count) AS fire_station_flooded_building_count,
            sum(a.school_building_count) AS school_flooded_building_count,
            sum(a.university_building_count) AS university_flooded_building_count,
            sum(a.government_building_count) AS government_flooded_building_count,
            sum(a.hospital_building_count) AS hospital_flooded_building_count,
            sum(a.police_station_building_count) AS police_station_flooded_building_count,
            sum(a.supermarket_building_count) AS supermarket_flooded_building_count,
            sum(a.sports_facility_building_count) AS sports_facility_flooded_building_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_building_summary.flood_event_id,
                    mv_flooded_building_summary.district_id,
                    mv_flooded_building_summary.sub_district_id,
                    mv_flooded_building_summary.village_id,
                    mv_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count,
                    mv_flooded_building_summary.total_vulnerability_score
                   FROM public.mv_flooded_building_summary
                  WHERE ((mv_flooded_building_summary.district_id IS NOT NULL) AND (mv_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_flooded_building_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.sub_district_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            sub_district.name,
            a.flooded_building_count,
            b_1.building_count,
            b_1.residential_building_count,
            b_1.clinic_dr_building_count,
            b_1.fire_station_building_count,
            b_1.school_building_count,
            b_1.university_building_count,
            b_1.government_building_count,
            b_1.hospital_building_count,
            b_1.police_station_building_count,
            b_1.supermarket_building_count,
            b_1.sports_facility_building_count,
            a.residential_flooded_building_count,
            a.clinic_dr_flooded_building_count,
            a.fire_station_flooded_building_count,
            a.school_flooded_building_count,
            a.university_flooded_building_count,
            a.government_flooded_building_count,
            a.hospital_flooded_building_count,
            a.police_station_flooded_building_count,
            a.supermarket_flooded_building_count,
            a.sports_facility_flooded_building_count,
            a.total_vulnerability_score
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON (((a.district_id = b_1.district_id) AND (a.sub_district_id = b_1.sub_district_id))))
             JOIN public.sub_district ON ((sub_district.sub_dc_code = a.sub_district_id)))
        )
 SELECT flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.sub_district_id,
    flooded_aggregate_count.name,
    flooded_aggregate_count.building_count,
    flooded_aggregate_count.flooded_building_count,
    flooded_aggregate_count.total_vulnerability_score,
    flooded_aggregate_count.residential_flooded_building_count,
    flooded_aggregate_count.clinic_dr_flooded_building_count,
    flooded_aggregate_count.fire_station_flooded_building_count,
    flooded_aggregate_count.school_flooded_building_count,
    flooded_aggregate_count.university_flooded_building_count,
    flooded_aggregate_count.government_flooded_building_count,
    flooded_aggregate_count.hospital_flooded_building_count,
    flooded_aggregate_count.police_station_flooded_building_count,
    flooded_aggregate_count.supermarket_flooded_building_count,
    flooded_aggregate_count.sports_facility_flooded_building_count,
    flooded_aggregate_count.residential_building_count,
    flooded_aggregate_count.clinic_dr_building_count,
    flooded_aggregate_count.fire_station_building_count,
    flooded_aggregate_count.school_building_count,
    flooded_aggregate_count.university_building_count,
    flooded_aggregate_count.government_building_count,
    flooded_aggregate_count.hospital_building_count,
    flooded_aggregate_count.police_station_building_count,
    flooded_aggregate_count.supermarket_building_count,
    flooded_aggregate_count.sports_facility_building_count,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.sub_district_trigger_status b ON (((b.sub_district_id = (flooded_aggregate_count.sub_district_id)::double precision) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: village_trigger_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.village_trigger_status (
    id integer NOT NULL,
    village_id double precision,
    trigger_status integer,
    flood_event_id integer
);


--
-- Name: mv_flood_event_village_summary; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.mv_flood_event_village_summary AS
 WITH non_flooded_count_selection AS (
         SELECT b_1.district_id,
            b_1.sub_district_id,
            b_1.village_id,
            sum(b_1.building_type_count) AS building_count,
            sum(b_1.residential_building_count) AS residential_building_count,
            sum(b_1.clinic_dr_building_count) AS clinic_dr_building_count,
            sum(b_1.fire_station_building_count) AS fire_station_building_count,
            sum(b_1.school_building_count) AS school_building_count,
            sum(b_1.university_building_count) AS university_building_count,
            sum(b_1.government_building_count) AS government_building_count,
            sum(b_1.hospital_building_count) AS hospital_building_count,
            sum(b_1.police_station_building_count) AS police_station_building_count,
            sum(b_1.supermarket_building_count) AS supermarket_building_count,
            sum(b_1.sports_facility_building_count) AS sports_facility_building_count
           FROM ( SELECT DISTINCT mv_non_flooded_building_summary.district_id,
                    mv_non_flooded_building_summary.sub_district_id,
                    mv_non_flooded_building_summary.village_id,
                    mv_non_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_non_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_non_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count
                   FROM public.mv_non_flooded_building_summary
                  WHERE ((mv_non_flooded_building_summary.district_id IS NOT NULL) AND (mv_non_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_non_flooded_building_summary.village_id IS NOT NULL))) b_1
          GROUP BY b_1.district_id, b_1.sub_district_id, b_1.village_id
        ), flooded_count_selection AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            a.village_id,
            sum(a.building_type_count) AS flooded_building_count,
            sum(a.residential_building_count) AS residential_flooded_building_count,
            sum(a.clinic_dr_building_count) AS clinic_dr_flooded_building_count,
            sum(a.fire_station_building_count) AS fire_station_flooded_building_count,
            sum(a.school_building_count) AS school_flooded_building_count,
            sum(a.university_building_count) AS university_flooded_building_count,
            sum(a.government_building_count) AS government_flooded_building_count,
            sum(a.hospital_building_count) AS hospital_flooded_building_count,
            sum(a.police_station_building_count) AS police_station_flooded_building_count,
            sum(a.supermarket_building_count) AS supermarket_flooded_building_count,
            sum(a.sports_facility_building_count) AS sports_facility_flooded_building_count,
            sum(a.total_vulnerability_score) AS total_vulnerability_score
           FROM ( SELECT DISTINCT mv_flooded_building_summary.flood_event_id,
                    mv_flooded_building_summary.district_id,
                    mv_flooded_building_summary.sub_district_id,
                    mv_flooded_building_summary.village_id,
                    mv_flooded_building_summary.building_type_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Residential'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS residential_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Clinic/Doctor'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS clinic_dr_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Fire Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS fire_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'School'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS school_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'University/College'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS university_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Government'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS government_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Hospital'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS hospital_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Police Station'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS police_station_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Supermarket'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS supermarket_building_count,
                        CASE
                            WHEN ((mv_flooded_building_summary.building_type)::text = 'Sports Facility'::text) THEN mv_flooded_building_summary.building_type_count
                            ELSE (0)::bigint
                        END AS sports_facility_building_count,
                    mv_flooded_building_summary.total_vulnerability_score
                   FROM public.mv_flooded_building_summary
                  WHERE ((mv_flooded_building_summary.district_id IS NOT NULL) AND (mv_flooded_building_summary.sub_district_id IS NOT NULL) AND (mv_flooded_building_summary.village_id IS NOT NULL))) a
          GROUP BY a.district_id, a.sub_district_id, a.village_id, a.flood_event_id
        ), flooded_aggregate_count AS (
         SELECT a.flood_event_id,
            a.district_id,
            a.sub_district_id,
            a.village_id,
            village.name,
            a.flooded_building_count,
            b_1.building_count,
            b_1.residential_building_count,
            b_1.clinic_dr_building_count,
            b_1.fire_station_building_count,
            b_1.school_building_count,
            b_1.university_building_count,
            b_1.government_building_count,
            b_1.hospital_building_count,
            b_1.police_station_building_count,
            b_1.supermarket_building_count,
            b_1.sports_facility_building_count,
            a.residential_flooded_building_count,
            a.clinic_dr_flooded_building_count,
            a.fire_station_flooded_building_count,
            a.school_flooded_building_count,
            a.university_flooded_building_count,
            a.government_flooded_building_count,
            a.hospital_flooded_building_count,
            a.police_station_flooded_building_count,
            a.supermarket_flooded_building_count,
            a.sports_facility_flooded_building_count,
            a.total_vulnerability_score
           FROM ((flooded_count_selection a
             JOIN non_flooded_count_selection b_1 ON (((a.district_id = b_1.district_id) AND (a.sub_district_id = b_1.sub_district_id) AND (a.village_id = b_1.village_id))))
             JOIN public.village ON ((village.village_code = a.village_id)))
        )
 SELECT flooded_aggregate_count.flood_event_id,
    flooded_aggregate_count.district_id,
    flooded_aggregate_count.sub_district_id,
    flooded_aggregate_count.village_id,
    flooded_aggregate_count.name,
    flooded_aggregate_count.building_count,
    flooded_aggregate_count.flooded_building_count,
    flooded_aggregate_count.total_vulnerability_score,
    flooded_aggregate_count.residential_flooded_building_count,
    flooded_aggregate_count.clinic_dr_flooded_building_count,
    flooded_aggregate_count.fire_station_flooded_building_count,
    flooded_aggregate_count.school_flooded_building_count,
    flooded_aggregate_count.university_flooded_building_count,
    flooded_aggregate_count.government_flooded_building_count,
    flooded_aggregate_count.hospital_flooded_building_count,
    flooded_aggregate_count.police_station_flooded_building_count,
    flooded_aggregate_count.supermarket_flooded_building_count,
    flooded_aggregate_count.sports_facility_flooded_building_count,
    flooded_aggregate_count.residential_building_count,
    flooded_aggregate_count.clinic_dr_building_count,
    flooded_aggregate_count.fire_station_building_count,
    flooded_aggregate_count.school_building_count,
    flooded_aggregate_count.university_building_count,
    flooded_aggregate_count.government_building_count,
    flooded_aggregate_count.hospital_building_count,
    flooded_aggregate_count.police_station_building_count,
    flooded_aggregate_count.supermarket_building_count,
    flooded_aggregate_count.sports_facility_building_count,
    b.trigger_status
   FROM (flooded_aggregate_count
     LEFT JOIN public.village_trigger_status b ON (((b.village_id = flooded_aggregate_count.village_id) AND (flooded_aggregate_count.flood_event_id = b.flood_event_id))))
  WITH NO DATA;


--
-- Name: osm_admin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_admin (
    geometry public.geometry(Geometry,4326),
    gid integer,
    osm_id numeric,
    name character varying(254),
    type character varying(254),
    admin_level bigint,
    changeset_id integer,
    changeset_version integer,
    changeset_timestamp timestamp without time zone,
    changeset_user character varying
);


--
-- Name: osm_buildings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.osm_buildings_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: osm_buildings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.osm_buildings_id_seq OWNED BY public.osm_buildings.id;


--
-- Name: osm_flood_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.osm_flood_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: osm_flood_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.osm_flood_id_seq OWNED BY public.hazard.id;


--
-- Name: osm_roads_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.osm_roads_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: osm_roads_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.osm_roads_id_seq OWNED BY public.osm_roads.id;


--
-- Name: osm_summary_gavin; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_summary_gavin (
    district_id double precision,
    sub_district_id numeric,
    village_id double precision,
    building_type character varying(100),
    district_count bigint,
    sub_district_count bigint,
    village_count bigint,
    building_type_count bigint
);


--
-- Name: osm_waterways; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.osm_waterways (
    id integer NOT NULL,
    osm_id bigint NOT NULL,
    name character varying,
    boat boolean,
    intermittent boolean,
    "name:af" character varying,
    osm_type character varying,
    waterway character varying,
    geometry public.geometry(LineString,4326),
    waterway_id integer,
    changeset_id integer,
    changeset_version integer,
    changeset_timestamp timestamp without time zone,
    changeset_user character varying
);


--
-- Name: osm_waterways_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.osm_waterways_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: osm_waterways_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.osm_waterways_id_seq OWNED BY public.osm_waterways.id;


--
-- Name: progress_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.progress_status (
    id integer NOT NULL,
    status character varying(50)
);


--
-- Name: progress_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.progress_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: progress_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.progress_status_id_seq OWNED BY public.progress_status.id;


--
-- Name: province; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.province (
    id integer NOT NULL,
    geom public.geometry(MultiPolygon,4326),
    name character varying(50),
    prov_code double precision
);


--
-- Name: province_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.province_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: province_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.province_id_seq OWNED BY public.province.id;


--
-- Name: report_notes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.report_notes (
    id integer NOT NULL,
    notes text,
    hazard_type integer,
    "order" integer
);


--
-- Name: report_notes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.report_notes_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: report_notes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.report_notes_id_seq OWNED BY public.report_notes.id;


--
-- Name: reporting_point; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reporting_point (
    id bigint NOT NULL,
    glofas_id bigint,
    name character varying(80),
    geometry public.geometry(Point,4326)
);


--
-- Name: reporting_point_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.reporting_point_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: reporting_point_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.reporting_point_id_seq OWNED BY public.reporting_point.id;


--
-- Name: road_type_class; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.road_type_class (
    id integer NOT NULL,
    road_class character varying(100)
);


--
-- Name: road_type_class_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.road_type_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: road_type_class_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.road_type_class_id_seq OWNED BY public.road_type_class.id;


--
-- Name: spreadsheet_reports; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.spreadsheet_reports (
    id integer NOT NULL,
    flood_event_id integer,
    spreadsheet bytea
);


--
-- Name: spreadsheet_reports_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.spreadsheet_reports_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: spreadsheet_reports_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.spreadsheet_reports_id_seq OWNED BY public.spreadsheet_reports.id;


--
-- Name: sub_district_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sub_district_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sub_district_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sub_district_id_seq OWNED BY public.sub_district.id;


--
-- Name: sub_district_trigger_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.sub_district_trigger_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: sub_district_trigger_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.sub_district_trigger_status_id_seq OWNED BY public.sub_district_trigger_status.id;


--
-- Name: trigger_status; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.trigger_status (
    id integer NOT NULL,
    name character varying(255) NOT NULL
);


--
-- Name: trigger_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.trigger_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: trigger_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.trigger_status_id_seq OWNED BY public.trigger_status.id;


--
-- Name: village_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.village_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: village_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.village_id_seq OWNED BY public.village.id;


--
-- Name: village_trigger_status_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.village_trigger_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: village_trigger_status_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.village_trigger_status_id_seq OWNED BY public.village_trigger_status.id;


--
-- Name: vw_district_extent; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_district_extent AS
 SELECT district_extent.id,
    district_extent.id_code,
    public.st_xmin((district_extent.extent)::public.box3d) AS x_min,
    public.st_ymin((district_extent.extent)::public.box3d) AS y_min,
    public.st_xmax((district_extent.extent)::public.box3d) AS x_max,
    public.st_ymax((district_extent.extent)::public.box3d) AS y_max
   FROM ( SELECT district.id,
            district.dc_code AS id_code,
            public.st_extent(district.geom) AS extent
           FROM public.district
          GROUP BY district.id, district.dc_code) district_extent;


--
-- Name: vw_hazard_event_areas; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_hazard_event_areas AS
 SELECT a.geometry,
    d.id AS flood_event_id,
    c.id AS flood_map_id,
    a.depth_class
   FROM (((public.hazard_area a
     JOIN public.hazard_areas b ON ((a.id = b.flooded_area_id)))
     JOIN public.hazard_map c ON ((c.id = b.flood_map_id)))
     JOIN public.hazard_event d ON ((d.flood_map_id = c.id)));


--
-- Name: vw_hazard_event_buildings_map; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_hazard_event_buildings_map AS
 SELECT row_number() OVER () AS id,
    b.geometry,
    b.building_type,
    b.district_id,
    b.sub_district_id,
    b.village_id,
    feb.depth_class_id,
    feb.flood_event_id
   FROM public.osm_buildings b,
    public.hazard_event_buildings feb
  WHERE (feb.building_id = b.id);


--
-- Name: VIEW vw_hazard_event_buildings_map; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON VIEW public.vw_hazard_event_buildings_map IS 'Flooded event buildings map view. Added by Tim to show when we select a flood.';


--
-- Name: vw_hazard_event_extent; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_hazard_event_extent AS
 SELECT flood_extent.id,
    public.st_xmin((flood_extent.extent)::public.box3d) AS x_min,
    public.st_ymin((flood_extent.extent)::public.box3d) AS y_min,
    public.st_xmax((flood_extent.extent)::public.box3d) AS x_max,
    public.st_ymax((flood_extent.extent)::public.box3d) AS y_max
   FROM ( SELECT hazard_event.id,
            public.st_extent(hazard_area.geometry) AS extent
           FROM (((public.hazard_event
             JOIN public.hazard_map ON ((hazard_event.flood_map_id = hazard_map.id)))
             JOIN public.hazard_areas ON ((hazard_map.id = hazard_areas.flood_map_id)))
             JOIN public.hazard_area ON ((hazard_areas.flooded_area_id = hazard_area.id)))
          GROUP BY hazard_event.id) flood_extent;


--
-- Name: vw_hazard_wkt_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_hazard_wkt_view AS
 SELECT hazard.id,
    hazard.name,
    public.st_astext(hazard.geometry) AS st_astext,
    hazard.source,
    hazard.reporting_date_time,
    hazard.forecast_date_time,
    hazard.station
   FROM public.hazard;


--
-- Name: vw_sub_district_extent; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_sub_district_extent AS
 SELECT subdistrict_extent.id,
    subdistrict_extent.id_code,
    public.st_xmin((subdistrict_extent.extent)::public.box3d) AS x_min,
    public.st_ymin((subdistrict_extent.extent)::public.box3d) AS y_min,
    public.st_xmax((subdistrict_extent.extent)::public.box3d) AS x_max,
    public.st_ymax((subdistrict_extent.extent)::public.box3d) AS y_max
   FROM ( SELECT sub_district.id,
            sub_district.sub_dc_code AS id_code,
            public.st_extent(sub_district.geom) AS extent
           FROM public.sub_district
          GROUP BY sub_district.id, sub_district.sub_dc_code) subdistrict_extent;


--
-- Name: vw_village_extent; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.vw_village_extent AS
 SELECT village_extent.id,
    village_extent.id_code,
    public.st_xmin((village_extent.extent)::public.box3d) AS x_min,
    public.st_ymin((village_extent.extent)::public.box3d) AS y_min,
    public.st_xmax((village_extent.extent)::public.box3d) AS x_max,
    public.st_ymax((village_extent.extent)::public.box3d) AS y_max
   FROM ( SELECT village.id,
            village.village_code AS id_code,
            public.st_extent(village.geom) AS extent
           FROM public.village
          GROUP BY village.id, village.village_code) village_extent;


--
-- Name: waterway_type_class; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.waterway_type_class (
    id integer NOT NULL,
    waterway_class character varying(100)
);


--
-- Name: waterway_type_class_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.waterway_type_class_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: waterway_type_class_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.waterway_type_class_id_seq OWNED BY public.waterway_type_class.id;


--
-- Name: building_type_class id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.building_type_class ALTER COLUMN id SET DEFAULT nextval('public.building_type_class_id_seq'::regclass);


--
-- Name: clip ogc_fid; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clip ALTER COLUMN ogc_fid SET DEFAULT nextval('public.clip_ogc_fid_seq'::regclass);


--
-- Name: district id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.district ALTER COLUMN id SET DEFAULT nextval('public.district_id_seq'::regclass);


--
-- Name: district_trigger_status id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.district_trigger_status ALTER COLUMN id SET DEFAULT nextval('public.district_trigger_status_id_seq'::regclass);


--
-- Name: hazard id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard ALTER COLUMN id SET DEFAULT nextval('public.osm_flood_id_seq'::regclass);


--
-- Name: hazard_area id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_area ALTER COLUMN id SET DEFAULT nextval('public.flooded_area_id_seq'::regclass);


--
-- Name: hazard_areas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_areas ALTER COLUMN id SET DEFAULT nextval('public.flooded_areas_id_seq'::regclass);


--
-- Name: hazard_class id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_class ALTER COLUMN id SET DEFAULT nextval('public.depth_class_id_seq'::regclass);


--
-- Name: hazard_event id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event ALTER COLUMN id SET DEFAULT nextval('public.forecast_flood_event_id_seq'::regclass);


--
-- Name: hazard_event_buildings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event_buildings ALTER COLUMN id SET DEFAULT nextval('public.flood_event_buildings_id_seq'::regclass);


--
-- Name: hazard_map id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_map ALTER COLUMN id SET DEFAULT nextval('public.flood_map_id_seq'::regclass);


--
-- Name: hazard_type id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_type ALTER COLUMN id SET DEFAULT nextval('public.hazard_type_id_seq'::regclass);


--
-- Name: layer_styles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.layer_styles ALTER COLUMN id SET DEFAULT nextval('public.layer_styles_id_seq'::regclass);


--
-- Name: osm_buildings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_buildings ALTER COLUMN id SET DEFAULT nextval('public.osm_buildings_id_seq'::regclass);


--
-- Name: osm_roads id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_roads ALTER COLUMN id SET DEFAULT nextval('public.osm_roads_id_seq'::regclass);


--
-- Name: osm_waterways id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_waterways ALTER COLUMN id SET DEFAULT nextval('public.osm_waterways_id_seq'::regclass);


--
-- Name: progress_status id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.progress_status ALTER COLUMN id SET DEFAULT nextval('public.progress_status_id_seq'::regclass);


--
-- Name: province id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.province ALTER COLUMN id SET DEFAULT nextval('public.province_id_seq'::regclass);


--
-- Name: report_notes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_notes ALTER COLUMN id SET DEFAULT nextval('public.report_notes_id_seq'::regclass);


--
-- Name: reporting_point id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporting_point ALTER COLUMN id SET DEFAULT nextval('public.reporting_point_id_seq'::regclass);


--
-- Name: road_type_class id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.road_type_class ALTER COLUMN id SET DEFAULT nextval('public.road_type_class_id_seq'::regclass);


--
-- Name: spreadsheet_reports id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spreadsheet_reports ALTER COLUMN id SET DEFAULT nextval('public.spreadsheet_reports_id_seq'::regclass);


--
-- Name: sub_district id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_district ALTER COLUMN id SET DEFAULT nextval('public.sub_district_id_seq'::regclass);


--
-- Name: sub_district_trigger_status id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_district_trigger_status ALTER COLUMN id SET DEFAULT nextval('public.sub_district_trigger_status_id_seq'::regclass);


--
-- Name: trigger_status id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_status ALTER COLUMN id SET DEFAULT nextval('public.trigger_status_id_seq'::regclass);


--
-- Name: village id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.village ALTER COLUMN id SET DEFAULT nextval('public.village_id_seq'::regclass);


--
-- Name: village_trigger_status id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.village_trigger_status ALTER COLUMN id SET DEFAULT nextval('public.village_trigger_status_id_seq'::regclass);


--
-- Name: waterway_type_class id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.waterway_type_class ALTER COLUMN id SET DEFAULT nextval('public.waterway_type_class_id_seq'::regclass);


--
-- Name: clip clip_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.clip
    ADD CONSTRAINT clip_pkey PRIMARY KEY (ogc_fid);


--
-- Name: hazard_class depth_class_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_class
    ADD CONSTRAINT depth_class_pkey PRIMARY KEY (id);


--
-- Name: district district_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.district
    ADD CONSTRAINT district_pkey PRIMARY KEY (dc_code);


--
-- Name: district_trigger_status district_trigger_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.district_trigger_status
    ADD CONSTRAINT district_trigger_status_pkey PRIMARY KEY (id);


--
-- Name: hazard_event_buildings flood_event_buildings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event_buildings
    ADD CONSTRAINT flood_event_buildings_pkey PRIMARY KEY (id);


--
-- Name: hazard_map flood_map_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_map
    ADD CONSTRAINT flood_map_pkey PRIMARY KEY (id);


--
-- Name: hazard_area flooded_area_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_area
    ADD CONSTRAINT flooded_area_pkey PRIMARY KEY (id);


--
-- Name: hazard_areas flooded_areas_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_areas
    ADD CONSTRAINT flooded_areas_pkey PRIMARY KEY (id);


--
-- Name: hazard_event forecast_flood_event_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event
    ADD CONSTRAINT forecast_flood_event_pkey PRIMARY KEY (id);


--
-- Name: hazard_type hazard_type_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_type
    ADD CONSTRAINT hazard_type_pkey PRIMARY KEY (id);


--
-- Name: layer_styles layer_styles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.layer_styles
    ADD CONSTRAINT layer_styles_pkey PRIMARY KEY (id);


--
-- Name: osm_buildings osm_buildings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_buildings
    ADD CONSTRAINT osm_buildings_pkey PRIMARY KEY (osm_id);


--
-- Name: osm_roads osm_roads_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_roads
    ADD CONSTRAINT osm_roads_pkey PRIMARY KEY (osm_id, id);


--
-- Name: osm_waterways osm_waterways_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_waterways
    ADD CONSTRAINT osm_waterways_pkey PRIMARY KEY (osm_id, id);


--
-- Name: progress_status progress_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.progress_status
    ADD CONSTRAINT progress_status_pkey PRIMARY KEY (id);


--
-- Name: province province_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.province
    ADD CONSTRAINT province_pkey PRIMARY KEY (id);


--
-- Name: report_notes report_notes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_notes
    ADD CONSTRAINT report_notes_pkey PRIMARY KEY (id);


--
-- Name: reporting_point reporting_point_pk; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reporting_point
    ADD CONSTRAINT reporting_point_pk PRIMARY KEY (id);


--
-- Name: spreadsheet_reports spreadsheet_reports_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spreadsheet_reports
    ADD CONSTRAINT spreadsheet_reports_pkey PRIMARY KEY (id);


--
-- Name: trigger_status status_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_status
    ADD CONSTRAINT status_name_key UNIQUE (name);


--
-- Name: sub_district sub_district_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_district
    ADD CONSTRAINT sub_district_pkey PRIMARY KEY (sub_dc_code);


--
-- Name: sub_district_trigger_status sub_district_trigger_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_district_trigger_status
    ADD CONSTRAINT sub_district_trigger_status_pkey PRIMARY KEY (id);


--
-- Name: trigger_status trigger_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.trigger_status
    ADD CONSTRAINT trigger_status_pkey PRIMARY KEY (id);


--
-- Name: village village_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.village
    ADD CONSTRAINT village_pkey PRIMARY KEY (village_code);


--
-- Name: village_trigger_status village_trigger_status_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.village_trigger_status
    ADD CONSTRAINT village_trigger_status_pkey PRIMARY KEY (id);


--
-- Name: clip_wkb_geometry_geom_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX clip_wkb_geometry_geom_idx ON public.clip USING gist (geom);


--
-- Name: flood_event_idx_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flood_event_idx_id ON public.hazard_event USING btree (id);


--
-- Name: flood_event_idx_map_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flood_event_idx_map_id ON public.hazard_event USING btree (flood_map_id);


--
-- Name: flood_map_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flood_map_id ON public.hazard_map USING btree (id);


--
-- Name: flooded_area_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flooded_area_id ON public.hazard_area USING btree (id);


--
-- Name: flooded_area_idx_geometry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX flooded_area_idx_geometry ON public.hazard_area USING gist (geometry);


--
-- Name: id_osm_flood_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX id_osm_flood_idx ON public.hazard USING btree (id);


--
-- Name: id_osm_flood_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX id_osm_flood_name ON public.hazard USING btree (name);


--
-- Name: idx_osm_building_area_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_area_score ON public.osm_buildings USING btree (building_area_score);


--
-- Name: idx_osm_building_material_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_material_score ON public.osm_buildings USING btree (building_material_score);


--
-- Name: idx_osm_building_road_density_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_road_density_score ON public.osm_buildings USING btree (building_road_density_score);


--
-- Name: idx_osm_building_road_length; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_road_length ON public.osm_buildings USING btree (building_road_length);


--
-- Name: idx_osm_building_total_vulnerability; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_total_vulnerability ON public.osm_buildings USING btree (total_vulnerability);


--
-- Name: idx_osm_building_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_type ON public.osm_buildings USING btree (building_type);


--
-- Name: idx_osm_building_type_score; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_building_type_score ON public.osm_buildings USING btree (building_type_score);


--
-- Name: idx_osm_road; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_road ON public.osm_roads USING btree (road_type);


--
-- Name: idx_osm_roads_osm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_roads_osm_id ON public.osm_roads USING btree (osm_id);


--
-- Name: idx_osm_waterways_osm_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_waterways_osm_id ON public.osm_waterways USING btree (osm_id);


--
-- Name: idx_osm_waterways_way; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_osm_waterways_way ON public.osm_waterways USING btree (waterway);


--
-- Name: osm_buildings_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX osm_buildings_geom ON public.osm_buildings USING gist (geometry);


--
-- Name: osm_flood_gix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX osm_flood_gix ON public.hazard USING gist (geometry);


--
-- Name: osm_roads_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX osm_roads_geom ON public.osm_roads USING gist (geometry);


--
-- Name: osm_waterways_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX osm_waterways_geom ON public.osm_waterways USING gist (geometry);


--
-- Name: reporting_point_glofas_id_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reporting_point_glofas_id_uindex ON public.reporting_point USING btree (glofas_id);


--
-- Name: reporting_point_id_uindex; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX reporting_point_id_uindex ON public.reporting_point USING btree (id);


--
-- Name: sidx_district_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sidx_district_geom ON public.district USING gist (geom);


--
-- Name: sidx_province_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sidx_province_geom ON public.province USING gist (geom);


--
-- Name: sidx_sub_district_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sidx_sub_district_geom ON public.sub_district USING gist (geom);


--
-- Name: sidx_village_geom; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX sidx_village_geom ON public.village USING gist (geom);


--
-- Name: osm_buildings area_mapper_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER area_mapper_tg AFTER INSERT OR UPDATE ON public.osm_buildings FOR EACH ROW EXECUTE PROCEDURE public.kartoza_building_area_mapper();


--
-- Name: osm_buildings area_recode_mapper_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER area_recode_mapper_tg AFTER INSERT OR UPDATE ON public.osm_buildings FOR EACH ROW EXECUTE PROCEDURE public.kartoza_building_area_score_mapper();


--
-- Name: osm_buildings building_material_recode_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER building_material_recode_tg AFTER INSERT OR UPDATE ON public.osm_buildings FOR EACH ROW EXECUTE PROCEDURE public.kartoza_building_materials_mapper();


--
-- Name: osm_buildings building_type_mapper_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER building_type_mapper_tg AFTER INSERT OR UPDATE ON public.osm_buildings FOR EACH ROW EXECUTE PROCEDURE public.kartoza_building_types_mapper();


--
-- Name: osm_buildings building_type_recode_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER building_type_recode_tg AFTER INSERT OR UPDATE ON public.osm_buildings FOR EACH ROW EXECUTE PROCEDURE public.kartoza_building_recode_mapper();


--
-- Name: hazard_event flood_event_buildings_mv_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER flood_event_buildings_mv_tg AFTER INSERT ON public.hazard_event FOR EACH STATEMENT EXECUTE PROCEDURE public.kartoza_refresh_flood_event_buildings_mv();


--
-- Name: hazard_event flood_event_roads_mv_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER flood_event_roads_mv_tg AFTER INSERT ON public.hazard_event FOR EACH STATEMENT EXECUTE PROCEDURE public.kartoza_refresh_flood_event_roads_mv();


--
-- Name: spreadsheet_reports flood_report_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER flood_report_tg BEFORE INSERT ON public.spreadsheet_reports FOR EACH ROW EXECUTE PROCEDURE public.kartoza_generate_excel_report_for_flood();


--
-- Name: hazard_event game_non_flooded_roads_mv_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER game_non_flooded_roads_mv_tg AFTER INSERT ON public.hazard_event FOR EACH STATEMENT EXECUTE PROCEDURE public.kartoza_refresh_non_flooded_roads_summary_mv();


--
-- Name: hazard_event hame_flooded_roads_mv_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER hame_flooded_roads_mv_tg AFTER INSERT ON public.hazard_event FOR EACH STATEMENT EXECUTE PROCEDURE public.kartoza_refresh_flooded_roads_summary_mv();


--
-- Name: hazard_event home_non_flooded_fd_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER home_non_flooded_fd_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_flood_non_flooded_building_summary();


--
-- Name: hazard_event jade_dist_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jade_dist_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_flood_district_summary();


--
-- Name: hazard_event jade_roads_district_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER jade_roads_district_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_road_district_summary();


--
-- Name: hazard_event kade_roads_sub_district_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kade_roads_sub_district_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_road_sub_district_summary();


--
-- Name: hazard_event kalk_sub_fd_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER kalk_sub_fd_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_flood_sub_event_summary();


--
-- Name: hazard_event lade_roads_village_summary_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lade_roads_village_summary_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_road_village_summary();


--
-- Name: hazard_event lame_village_event_smry_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER lame_village_event_smry_tg AFTER INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_refresh_flood_village_event_summary();


--
-- Name: hazard_event z_event_populate_spreadsheet_flood_tg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER z_event_populate_spreadsheet_flood_tg BEFORE INSERT ON public.hazard_event FOR EACH ROW EXECUTE PROCEDURE public.kartoza_populate_spreadsheet_table();


--
-- Name: district_trigger_status district_trigger_status_trigger_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.district_trigger_status
    ADD CONSTRAINT district_trigger_status_trigger_status_fkey FOREIGN KEY (trigger_status) REFERENCES public.trigger_status(id);


--
-- Name: hazard_event_buildings flood_event_buildings_building_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event_buildings
    ADD CONSTRAINT flood_event_buildings_building_id_fkey FOREIGN KEY (building_id) REFERENCES public.osm_buildings(osm_id);


--
-- Name: hazard_event_buildings flood_event_buildings_depth_class_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event_buildings
    ADD CONSTRAINT flood_event_buildings_depth_class_id_fkey FOREIGN KEY (depth_class_id) REFERENCES public.hazard_class(id);


--
-- Name: hazard_event_buildings flood_event_buildings_flood_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event_buildings
    ADD CONSTRAINT flood_event_buildings_flood_event_id_fkey FOREIGN KEY (flood_event_id) REFERENCES public.hazard_event(id) ON DELETE CASCADE;


--
-- Name: hazard_event flood_event_progress_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event
    ADD CONSTRAINT flood_event_progress_fkey FOREIGN KEY (progress) REFERENCES public.progress_status(id);


--
-- Name: hazard_event flood_event_trigger_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event
    ADD CONSTRAINT flood_event_trigger_status_fkey FOREIGN KEY (trigger_status) REFERENCES public.trigger_status(id);


--
-- Name: hazard_map flood_map_reporting_point_id_fk; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_map
    ADD CONSTRAINT flood_map_reporting_point_id_fk FOREIGN KEY (measuring_station_id) REFERENCES public.reporting_point(id);


--
-- Name: hazard_area flooded_area_depth_class_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_area
    ADD CONSTRAINT flooded_area_depth_class_fkey FOREIGN KEY (depth_class) REFERENCES public.hazard_class(id);


--
-- Name: hazard_areas flooded_areas_flood_map_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_areas
    ADD CONSTRAINT flooded_areas_flood_map_id_fkey FOREIGN KEY (flood_map_id) REFERENCES public.hazard_map(id);


--
-- Name: hazard_areas flooded_areas_flooded_area_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_areas
    ADD CONSTRAINT flooded_areas_flooded_area_id_fkey FOREIGN KEY (flooded_area_id) REFERENCES public.hazard_area(id);


--
-- Name: hazard_event forecast_flood_event_flood_map_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event
    ADD CONSTRAINT forecast_flood_event_flood_map_id_fkey FOREIGN KEY (flood_map_id) REFERENCES public.hazard_map(id);


--
-- Name: hazard_event hazard_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.hazard_event
    ADD CONSTRAINT hazard_type_fkey FOREIGN KEY (hazard_type_id) REFERENCES public.hazard_type(id);


--
-- Name: osm_buildings osm_buildings_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_buildings
    ADD CONSTRAINT osm_buildings_district_id_fkey FOREIGN KEY (district_id) REFERENCES public.district(dc_code);


--
-- Name: osm_buildings osm_buildings_sub_district_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_buildings
    ADD CONSTRAINT osm_buildings_sub_district_id_fkey FOREIGN KEY (sub_district_id) REFERENCES public.sub_district(sub_dc_code);


--
-- Name: osm_buildings osm_buildings_village_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.osm_buildings
    ADD CONSTRAINT osm_buildings_village_id_fkey FOREIGN KEY (village_id) REFERENCES public.village(village_code);


--
-- Name: report_notes report_notes_hazard_type_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.report_notes
    ADD CONSTRAINT report_notes_hazard_type_fkey FOREIGN KEY (hazard_type) REFERENCES public.hazard_type(id);


--
-- Name: spreadsheet_reports spreadsheet_reports_flood_event_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.spreadsheet_reports
    ADD CONSTRAINT spreadsheet_reports_flood_event_id_fkey FOREIGN KEY (flood_event_id) REFERENCES public.hazard_event(id);


--
-- Name: sub_district_trigger_status sub_district_trigger_status_trigger_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sub_district_trigger_status
    ADD CONSTRAINT sub_district_trigger_status_trigger_status_fkey FOREIGN KEY (trigger_status) REFERENCES public.trigger_status(id);


--
-- Name: village_trigger_status village_trigger_status_trigger_status_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.village_trigger_status
    ADD CONSTRAINT village_trigger_status_trigger_status_fkey FOREIGN KEY (trigger_status) REFERENCES public.trigger_status(id);




--
-- PostgreSQL database dump complete
--







