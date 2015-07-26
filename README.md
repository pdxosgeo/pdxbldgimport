Portland, Oregon OSM Building Import
=============

This project is a community-lead effort to import [building data distributed by
Oregon Metro](http://rlisdiscovery.oregonmetro.gov/?action=viewDetail&layerID=2406) into [OpenStreetMap](https://www.openstreetmap.org).  

Get Involved
============
There are few ways to get involved:

* [Help with the import process](https://github.com/pdxosgeo/pdxbldgimport/wiki)
* [Update and improve documentation on the wiki](https://github.com/pdxosgeo/pdxbldgimport/wiki)
* [Help write and maintain code required to generate data for the import process](https://github.com/pdxosgeo/pdxbldgimport#requirements)

See the [OSM Wiki page for this project](http://wiki.openstreetmap.org/wiki/Portland,_OR_Bldg_import) for other details.


============

1. PostgreSQL (Postgres.app)
2. Osmosis (brew)
3. ruby, rake, bundler


Preparing
=========

Create a PostgreSQL database (e.g. pdx_bldgs). In your database, load extensions postgis and hstore. 
```
create database pdx_bldgs;
\connect pdx_bldgs
create extension postgis;
create extension hstore;
\quit
```

Edit the Rakefile to include your database configuration:

```
ENV['PGUSER']='myname'
ENV['PGDATABASE']='pdx_bldgs'
ENV['PGHOST']='myhost'
```

Create the OSM schema for your db from the scripts in your Osmosis directory.
```
psql pdx_bldgs -f pgsnapshot_schema_0.6.sql
psql pdx_bldgs -f pgsnapshot_schema_0.6_linestring.sql
```

Setup your repo. I use:

`bundle install --path=vendor --binstubs`

Loading the data
================

There are a number of rake tasks that will build the datasets.
You can see them with 'rake -T'

## General instructions

The tasks to download the data are not automatic, you will have to run them manually.

There are a number of intermediate tables that get built and modified. The tasks to build these are in the tasks/*.rake files.

### fetch the data

```
bundle exec rake osm/bldgs.osm.bz2 pdx_bldg_download pdx_addr_download
cd osm && bunzip2 -k -d bldgs.osm.bz2
```

## load the data and generate all osm files
```
bundle exec rake gall_osm_files
```



