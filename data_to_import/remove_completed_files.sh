#!/bin/bash

for file in `fgrep '[x]' Import_Tasks.md| awk '{print $3}'`; do
  if [[ -f ${file}.osm ]]; then
    git rm ${file}.osm
    echo removing ${file}.osm
  fi
  if [[ -f ${file}_multi_addr.osm ]]; then
    git rm ${file}_multi_addr.osm
    echo removing ${file}_multi_addr.osm
  fi
done
