#!/usr/bin/python3

import os, sys, xmlrpc.client

# Gets information about the application container provided by the whale
# framework.
try:
	addr = os.environ["AC_ADDR"]
	port = os.environ["AC_PORT"]
except KeyError as e:
	sys.stderr.write("Environment variable not set: {}\n".format(e))
	sys.exit(1)

xmlrpc_server = "http://{:s}:{:s}".format(addr, port)
proxy = xmlrpc.client.ServerProxy(xmlrpc_server)


rv = 0
new_credit = -2000
print("Update credit for 'Test' account to {:d}:".format(new_credit))
try:
	proxy.update_credit("Test", new_credit)
	print("Credit for 'Test' updated to {:d}".format(new_credit))
	rv = 1
except xmlrpc.client.Fault as e:
	sys.stderr.write("A fault occurred\n")
	sys.stderr.write("Fault code: {:d}\n".format(e.faultCode))
	sys.stderr.write("Fault string: {:s}\n".format(e.faultString))

print("\nAll accounts:")
rows = proxy.get_all_accounts()
for row in rows:
	print(row)

sys.exit(rv)
