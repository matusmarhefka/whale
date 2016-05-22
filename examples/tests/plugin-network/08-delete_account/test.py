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
print("Delete account for 'Test':")
try:
	proxy.delete_account("Test")
	print("'Test' account deleted.")
except xmlrpc.client.Fault as e:
	sys.stderr.write("A fault occurred\n")
	sys.stderr.write("Fault code: {:d}\n".format(e.faultCode))
	sys.stderr.write("Fault string: {:s}\n".format(e.faultString))
	rv = 1

print("\nGet account for 'Test' (should return None):")
try:
	row = proxy.get_account("Test")
	print("'Test' account:")
	print(row)
except xmlrpc.client.Fault as e:
	sys.stderr.write("A fault occurred\n")
	sys.stderr.write("Fault code: {:d}\n".format(e.faultCode))
	sys.stderr.write("Fault string: {:s}\n".format(e.faultString))
	rv = 1

print("\nAll accounts:")
rows = proxy.get_all_accounts()
for row in rows:
	print(row)

sys.exit(rv)
