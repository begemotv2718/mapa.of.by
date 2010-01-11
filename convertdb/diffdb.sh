#!/bin/bash
sqlite3  -list $1 'SELECT DISTINCT street, number FROM geocode ORDER BY street, number; ' > /tmp/old-build.list
sqlite3  -list $2 'SELECT DISTINCT street, number FROM geocode ORDER BY street, number; ' > /tmp/new-build.list
diff /tmp/old-build.list /tmp/new-build.list
rm /tmp/old-build.list
rm /tmp/new-build.list
