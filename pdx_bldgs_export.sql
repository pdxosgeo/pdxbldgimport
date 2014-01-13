DROP VIEW IF EXISTS pdx_bldgs_export;
CREATE OR REPLACE VIEW pdx_bldgs_export AS
SELECT imports.* FROM (
  SELECT a.housenumber,
       a.street,
       a.postcode,
       a.city,
       a.state,
       a.country,
       p.bldg_id,
       p.levels,
       p.ele,
       p.height,
       p.name,
       p.bldg_use,
       case bldg_use
         WHEN 'Commercial General' THEN 'commerical'
         WHEN 'Commercial Grocery' THEN 'retail'
         WHEN 'Commercial Hotel' THEN 'hotel'
         WHEN 'Commercial Office' THEN 'office'
         WHEN 'Commercial Restaurant' THEN 'commerical'
         WHEN 'Commercial Retail' THEN 'retail'
         WHEN 'Industrial' THEN 'industrial'
         WHEN 'Institutional Religious' THEN 'church'
         WHEN 'Multi Family Residential' THEN 'apartments'
         WHEN 'Parking' THEN 'garage'
         WHEN 'Single Family Residential' THEN 'residential'
         ELSE 'yes' 
       END as building,
       p.no_addrs,
       the_geom

  FROM pdx_bldgs p
     JOIN pdx_addrs a ON (a.address_id=p.address_id)
     -- JOIN osm_buildings o ON (st_disjoint(p.the_geom,o.the_geom))
  WHERE no_addrs = 1
    AND st_intersects(p.the_geom,
                      (SELECT st_setsrid(st_extent(the_geom),4326)
                       FROM osm_buildings))
) imports
LEFT OUTER JOIN osm_buildings o ON (st_intersects(o.the_geom,imports.the_geom))
WHERE o.the_geom IS NULL;
