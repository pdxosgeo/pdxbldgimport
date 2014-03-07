Portland, Oregon OSM Building Import Process
=============

The OSM Wiki page for this project is here: http://wiki.openstreetmap.org/wiki/Portland,_OR_Bldg_import

Because of its size, this repo does not contain the actual data. Just the code to manipulate it.

Requirements
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

