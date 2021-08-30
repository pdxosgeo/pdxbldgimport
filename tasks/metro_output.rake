desc "Remove all the output files"
task :remove_osm_files do |t|
  sh %Q{/bin/rm -f shps/[12345]*}
end
desc "Generate all OSM file chunks"
task :all_osm_files do |t|
  Rake::Task.tasks.each do |task|
    # run any task that matches an osm file that should exist. (See below)
    task.invoke if task.name =~ /^shps\/.*osm/ 
  end
end

# finally generate the tasks that spit out our data to load into josm
if DB.tables.include?(:consolidated_qtr_secs)
  @qtr_secs=DB[:consolidated_qtr_secs].map(:qtrsec).uniq
  # puts "qtr_secs: #{@qtr_secs}"
  @qtr_secs.sort.each do |qtrsec|
    # ['','_multi_addr'].each do |type|
    [''].each do |type|
      shp_fn="shps/#{qtrsec}#{type}.shp"
      osm_fn="shps/#{qtrsec}#{type}.osm"

      # yes, this is ugly. I'm sorry.
      if type == '' 
        sql = %Q{
          SELECT property_id,
                q.qtrsec ,
                addr_housenumber as housenum,
                addr_street as street,
                addr_postcode as postcode,
                addr_city as city,
                addr_state as state,
                addr_country as country,
                NULLIF(levels,0) as levels,
                NULLIF(ele,0) as ele,
                NULLIF(height,0) as height,
                bldg_type,
                no_addrs,
                b.the_geom
                FROM metro_bldgs b
                JOIN consolidated_qtr_secs q ON (ST_Intersects(q.the_geom,b.the_geom_centroids))
                WHERE q.qtrsec='#{qtrsec}'
                ORDER BY q.qtrsec,6,5
        }
      else 
        sql = %Q{
          SELECT state_id,
                pdx_bldg_id as pdx_bldg_i,
                housenumber as housenum,
                street,
                postcode,
                city,
                state,
                the_geom,
                qtrsec 
                FROM pdx_bldgs_multi_addrs 
                WHERE qtrsec='#{qtrsec}'
                ORDER BY qtrsec,4,3
        }
      end #if multi

      file shp_fn => [:metro_bldgs] do
        sh %Q{ogr2ogr -overwrite -f "ESRI Shapefile" -a_srs EPSG:4326 #{shp_fn} PG:"" \
        -sql "#{sql}"
            }
      end #file shp_fn

      file osm_fn => shp_fn do
        sh %Q{ if [[ -f "#{osm_fn}" ]]; then rm "#{osm_fn}"; fi}
        # sh %Q{python #{__dir__}/../../ogr2osm/ogr2osm.py "#{shp_fn}" \
        sh %Q{/usr/local/bin/ogr2osm "#{shp_fn}" \
        -o "#{osm_fn}" \
        -t #{__dir__}/../scripts/pdx_bldg_translate.py}
      end #file osm_fn
    end #type
  end #qtr_sec
end


