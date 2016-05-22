#!/bin/bash

if [ -d "/" ]; then
	echo "PASS: / is a directory"
else
	echo "FAIL: / is not a directory"
fi
