
desc "Load taxlots data"
table :taxlots => shapefile('./rlis/TAXLOTS/taxlots.shp') do |t|
  # t.drop_table
  # t.load_shapefile(t.prerequisites.first, :append => false)
  t.add_centroids
  t.add_index :tlid
end