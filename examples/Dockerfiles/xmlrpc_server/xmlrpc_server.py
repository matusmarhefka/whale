#!/usr/bin/python3

import sys, os, time
import MySQLdb as mdb
from xmlrpc.server import SimpleXMLRPCServer
import xmlrpc.client


# Gets information about mariadb container.
try:
	hostname = os.environ["HOSTNAME"]
	addr = os.environ["MARIADB_PORT_3306_TCP_ADDR"]
	port = os.environ["MARIADB_PORT_3306_TCP_PORT"]
	passw = os.environ["MARIADB_ENV_MYSQL_ROOT_PASSWORD"]
	dbname = os.environ["MARIADB_ENV_MYSQL_DATABASE"]
except KeyError as e:
	sys.stderr.write("Environment variable not set: {}\n".format(e))
	sys.exit(1)

def _check_alpha(s):
	if s.isalpha() == False:
		raise xmlrpc.client.Fault(1, "Name cannot be empty.")

def _check_num(n):
	try:
		int(n)
		return True
	except ValueError:
		raise xmlrpc.client.Fault(1, "Credit must be a number.")

################################################################################
# XMLRPC interface
################################################################################

# Returns the whole Accounts table as list of lists.
def get_all_accounts():
	print("-- get_all_accounts")
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		cur.execute("SELECT * FROM Accounts")
		rows = cur.fetchall()
	return rows

# Returns a row of the Accounts table for a customer with name 'name[string]'.
# The row is returned as a list. If no account is found for a customer, None
# is returned.
def get_account(name):
	print("-- get_account: [", name, "]")
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		sql = "SELECT Id,Name,Address,Credit FROM Accounts WHERE" \
			" Name='{:s}'".format(name)
		cur.execute(sql)
		row = cur.fetchone()
	return row

# Adds a row to the Accounts table with a new customer with:
# 'name[string]', 'address[string], 'credit[int]'.
# Returns None.
def add_account(name, address, credit):
	print("-- add_account: [", name, address, credit, "]")
	_check_alpha(name)
	_check_num(credit)
	if get_account(name) != None:
		raise xmlrpc.client.Fault(1, \
			"Duplicate name: '{:s}'".format(name))
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		tblin = "INSERT INTO Accounts(Name, Address, Credit) "
		sql = "VALUES('{:s}', '{:s}', {:s})".format(name, address, \
			str(credit))
		cur.execute(tblin + sql)

# Deletes a row of the Accounts table with a customer name 'name[string]'.
# Returns None.
def delete_account(name):
	print("-- delete_account: [", name, "]")
	if get_account(name) == None:
		raise xmlrpc.client.Fault(1, \
			"No such name: '{:s}'".format(name))
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		sql = "DELETE FROM Accounts WHERE Name='{:s}'".format(name)
		cur.execute(sql)

# Returns a credit value (as integer) of a customer with name 'name[string]'
# from the Accounts table.
def get_credit(name):
	print("-- get_credit: [", name, "]")
	if get_account(name) == None:
		raise xmlrpc.client.Fault(1, \
			"No such name: '{:s}'".format(name))
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		sql = "SELECT Credit FROM Accounts WHERE" \
			" Name='{:s}'".format(name)
		cur.execute(sql)
		row = cur.fetchone()
	return row[0]

# Updates the current credit of a customer with name 'name[string]'
# with the value 'val[int]' in the Accounts table.
# Returns None.
def update_credit(name, credit):
	print("-- update_credit: [", name, credit, "]")
	if get_account(name) == None:
		raise xmlrpc.client.Fault(1, \
			"No such name: '{:s}'".format(name))
	_check_num(credit)
	if credit < 0:
		raise xmlrpc.client.Fault(1, \
			"Credit value cannot be less than 0.")
	db = mdb.connect(host=addr, user='root', passwd=passw, db=dbname, \
		port=int(port))
	with db:
		cur = db.cursor()
		sql = "UPDATE Accounts SET Credit={:d}" \
			" WHERE Name='{:s}'".format(credit, name)
		cur.execute(sql)
################################################################################


print("XMLRPC hostname: {:s}".format(hostname))
print("   mariadb addr: {:s}".format(addr))
print("   mariadb port: {:s}".format(port))
print("  mariadb passw: {:s}".format(passw))
print(" mariadb dbname: {:s}".format(dbname))


db = None
tries = 0
while tries < 30:
	try:
		db = mdb.connect(host=addr, user='root', passwd=passw, \
			db=dbname, port=int(port))
	except:
		tries += 1
		time.sleep(2)
		continue
	break
if db == None:
	sys.stderr.write("Error: Unable to connect to {:s}:{:s}".format(addr, \
		port))
	sys.exit(1)

with db:
	# Fills database dbname with table Accounts and some rows if table
	# Accounts does not exist.
	cur = db.cursor()
	try:
		cur.execute("SELECT * FROM Accounts")
	except:
		print("Creating table 'Accounts'")
		cur.execute("CREATE TABLE Accounts(Id INT PRIMARY KEY AUTO_INCREMENT," \
			+ " Name VARCHAR(50) NOT NULL UNIQUE," \
			+ " Address VARCHAR(255) NOT NULL," \
			+ " Credit INT(11) UNSIGNED DEFAULT 0)")
		tblin = "INSERT INTO Accounts(Name, Address, Credit) "
		cur.execute(tblin + "VALUES('Customer1', 'Street 1, City1', 25000)")
		cur.execute(tblin + "VALUES('Customer2', 'Street 2, City2', 13500)")
		cur.execute(tblin + "VALUES('Customer3', 'Street 3, City3', 1255000)")
		cur.execute(tblin + "VALUES('Customer4', 'Street 4, City4', 8450)")
		cur.execute(tblin + "VALUES('Customer5', 'Street 5, City5', 56720)")


# Registers XMLRPC interface and starts listening on port 8000.
server = SimpleXMLRPCServer((hostname, 8000), allow_none=True)
server.register_introspection_functions()
print("Listening on port 8000...")
server.register_function(get_all_accounts, "get_all_accounts")
server.register_function(get_account, "get_account")
server.register_function(add_account, "add_account")
server.register_function(delete_account, "delete_account")
server.register_function(get_credit, "get_credit")
server.register_function(update_credit, "update_credit")
server.serve_forever()
