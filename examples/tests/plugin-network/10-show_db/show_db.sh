#!/bin/bash
#
# This test accesses 'accounts' database in the 'xmlrpc_db' container directly,
# and it shows the whole table 'Accounts'.

docker exec -t xmlrpc_db mysql \
	--password=pass \
	--database=accounts \
	--execute="SELECT * FROM Accounts"
