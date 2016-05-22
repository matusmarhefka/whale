#!/bin/bash
#
# $AC_ADDR and $AC_PORT environment variables must be exported automatically
# inside a test container and are referring to the container with the tested
# application.

rv=0
if [ -z "$AC_ADDR" ]; then
	printf "Environment variable AC_ADDR not set!\n"
	rv=1
else
	printf "AC_ADDR = $AC_ADDR\n"
fi

if [ -z "$AC_PORT" ]; then
	printf "Environment variable AC_PORT not set!\n"
	rv=1
else
	printf "AC_PORT = $AC_PORT\n"
fi

exit $rv
