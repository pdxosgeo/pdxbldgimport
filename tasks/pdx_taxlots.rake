
desc "Load taxlots data"
table :taxlots => shapefile('./rlis/TAXLOTS/taxlots.shp') do |t|
  t.run %Q{
    ALTER TABLE #{t.name} 
      ALTER COLUMN the_geom type geometry(MultiPolygon,4326)
      USING st_multi(the_geom);

    UPDATE #{t.name}
      SET the_geom=st_makevalid(the_geom)
      WHERE NOT st_isvalid(the_geom);
  }
  t.add_centroids
  t.add_index :tlid
end