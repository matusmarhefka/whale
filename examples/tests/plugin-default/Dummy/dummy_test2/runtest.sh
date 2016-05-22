#!/bin/bash

sleep 20
if [ $? -eq 0 ]; then
	echo "PASS: sleep successful"
else
	echo "FAIL: sleep failed"
fi

./test.sh
