FROM fedora

RUN dnf -y install python3 python3-mysql; dnf clean all

ADD xmlrpc_server.py /xmlrpc_server.py
RUN chmod -v +x /xmlrpc_server.py

EXPOSE 8000
CMD [ "python3", "/xmlrpc_server.py" ]
