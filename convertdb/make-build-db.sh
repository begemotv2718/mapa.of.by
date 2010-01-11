rm belarus.osm.bz2
wget -c http://downloads.cloudmade.com/europe/belarus/belarus.osm.bz2
bunzip belarus.osm.bz2
./osm2sqlite.pl belarus.sqlite belarus.osm
bzip2 belarus.osm
./osmsql2geocodesql.pl belarus.sqlite build.db
./testgeocode.pl build.db 
