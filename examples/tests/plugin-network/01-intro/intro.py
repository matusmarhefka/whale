#!/usr/bin/python3
#
# This test purpose is to wait for the xmlrpc_server to initialize to prevent
# tests depending on it from failing. This test should be run before all other
# tests accessing the xmlrpc_server.

import os, sys, time, xmlrpc.client

# Gets information about the application container.
try:
	addr = os.environ["AC_ADDR"]
	port = os.environ["AC_PORT"]
except KeyError as e:
	sys.stderr.write("Environment variable not set: {}\n".format(e))
	sys.exit(1)

xmlrpc_server = "http://{:s}:{:s}".format(addr, port)

while True:
	try:
		proxy = xmlrpc.client.ServerProxy(xmlrpc_server)
		# Print list of available methods
		print("List of XMLRPC available methods:")
		print(proxy.system.listMethods())
	except:
		time.sleep(2)
		continue
	break

sys.exit(0)
