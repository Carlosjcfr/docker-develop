#!/bin/bash
echo "\set pgpass 'mysecret'" > test.sql
echo "SELECT :'pgpass';" >> test.sql
echo "\set pgpass mysecret" > test2.sql
echo "SELECT :'pgpass';" >> test2.sql
