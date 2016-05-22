#!/bin/bash

printf "Got the following arguments: "
echo $@

OUT="dump.bin"
rv=$(dd if=/dev/urandom of=./$OUT bs=1M count=1)
if [ $? -ne 0 ]; then
	echo "$rv" 1>&2; exit 1
fi

rv=$(md5sum $OUT)
if [ $? -eq 0 ]; then
	echo "PASS: checksum: $rv"
	exit 0
else
	echo "$rv" 1>&2
	exit 1
fi
