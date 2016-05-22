#!/bin/bash

echo "Sleeping 60s..."
sleep 60
if [ $? -eq 0 ]; then
	echo "PASS: sleep successful"
	exit 0
else
	echo "FAIL: sleep failed"
	exit 1
fi
