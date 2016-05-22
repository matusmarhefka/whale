#!/bin/bash
#
# whale -- the framework for testing software running in Docker containers.
# Copyright (C) 2016, Red Hat, Inc., Matus Marhefka <mmarhefk@redhat.com>
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#
#
# DESCRIPTION:
# ============
# This file provides functions for creating Dockerfiles from a root test
# directory structure and recipe configuration files. Functions are also
# responsible for creating recipe file if it does not exist. Supervisor is
# used for running and monitoring tests and logging tests output.
#
#===============================================================================

# Adds test configuration into the supervisord.conf file for each test
# directory. All files are created inside a DOCKERFILE_DIR directory (specified
# as the fist argument). Returns 0 on success, 1 on error.
add_test() {
	if [ ! -d "$1" ] || [ -z "$2" ]; then
		eprintf "Error: add_test DOCKERFILE_DIR TEST_NAME\n"
		return 1
	fi

	# Checks if test name is not CONTROLLER which is reserved name
	# for the test controller.
	if [ "$2" == "CONTROLLER" ]; then
		eprintf "Error: Cannot use test name '$2': reserved name\n"
		return 1
	fi

	# Checks if test is already added.
	grep "program:$2" "$1/supervisord.conf" >/dev/null
	if [ $? -eq 0 ]; then return 0; fi

	local test_dir deps entrypoint timeout
	test_dir="$TESTS_ROOT_DIR/$2"

	if [ ! -f "$test_dir/$TEST_CONF" ]; then
		eprintf "Error: Configuration file missing: $test_dir/$TEST_CONF\n"
		eprintf "Try running 'make-conf' command first\n"
		return 1
	fi

	deps=$(ini_get true "$test_dir/$TEST_CONF" testinfo dependencies)
	DEPS="$DEPS $deps"
	entrypoint=$(ini_get false "$test_dir/$TEST_CONF" testinfo entrypoint) \
		|| return $?
	timeout=$(ini_get true "$test_dir/$TEST_CONF" testinfo timeout)
	if [ -z "$timeout" ]; then
		timeout=$DEFAULT_TIMEOUT
	fi

	printf "\n[program:$2]
command=/usr/bin/timeout $timeout $TESTS_DIR/$2/$entrypoint
directory=$TESTS_DIR/$2
autostart=false
autorestart=false
startretries=0
startsecs=0
exitcodes=0
stderr_logfile=$TESTS_DIR/$2/$(basename $2).log
stdout_logfile=$TESTS_DIR/$2/$(basename $2).log\n" >>"$1/supervisord.conf"

	return 0
}
#===============================================================================

# Creates Dockerfile and all the other files/directories inside a TEMP_DIR
# directory ($3 argument). Dockerfile FROM instruction will use the $1 argument
# and the CMD instruction will use the $2 argument. As plugin uses supervisor
# for tests management, supervisord.conf is created which includes all the tests
# specified in a $RECIPE file (global variable).
# Returns 0 on success, 1 on error.
plugin_create_dockerfile() {
	local status test_image tests temp_dir commands all_pkgs
	if [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		eprintf "Error: plugin_create_dockerfile IMAGE CMD TEMP_DIR\n"
		return 1
	fi

	DEPS=""  # all dependencies required for testing
	temp_dir="$3"

	# if RECIPE file does not exist, create one and open in nano for user
	# to edit it
	if [ ! -f "$RECIPE" ]; then
		cmd touch "$RECIPE" || return $?

		printf "; Configuration file for whale.
[global]
; An absolute path to the plugin directory for the whale framework; plugin
; is responsible for setup, deploying, running, monitoring tests and obtaining
; testing results from a test container.
; Required: yes
plugin=$PLUGIN_DIR

; An absolute path to the root directory with all the tests. Each test must
; have its own subdirectory inside this root directory. Test name is then set
; as a relative path to the test directory starting from this root directory.
; Required: yes
tests_root_dir=$TESTS_ROOT_DIR

; An additional options for docker-run command when launching a test container.
; It is possible to add various options, including volume mounts, options
; to create the super privileged container, or to limit resources for the test
; container.
; Required: no
docker_run_options=

; Specifies the default timeout for each test (same as timeout(1)). Tests which
; do not specify timeout value inside their $TEST_CONF configuration file use
; this default timeout value. When specified time passes test is terminated.
; Required: yes
default_timeout=5m

; Distribution specific package manager with command for installation
; and option to answer yes for all the questions.
;        Fedora: dnf install -y
; Debian/Ubuntu: apt-get update && apt-get install -y
; Required: yes
pkg_install=dnf install -y

; Distribution specific package manager with command for cleanup of temporary
; files for the currently enabled repositories.
;        Fedora: dnf clean all
; Debian/Ubuntu: apt-get clean
; Required: yes
tmp_files_cleanup=dnf clean all

; List of packages which should be available inside a test container, mainly
; for debugging purposes.
;        Fedora: strace procps-ng
; Debian/Ubuntu: strace procps
; Required: no
debug_pkgs=strace procps-ng

; Additional commands, which should be executed to extend the testing
; environment inside a test image or inside a test container. These commands
; are executed before the actual testing starts.
; The format should be one command per line.
; Required: no
[environment]
;wget -O /etc/yum.repos.d/beaker-client.repo https://beaker-project.org/yum/beaker-client-Fedora.repo
;dnf install -y beaker beakerlib
;dnf clean all

; Recipe for running specified tests inside a test container. Tests must be
; specified in form of a relative path starting from the 'tests_root_dir'
; directory specified as the parameter of the 'global' section. Tests specified
; on the same line will be run together parallelly. The same test cannot be run
; parallelly multiple times - this means that if one test entry is specified
; multiple times on the same line, it will be run only once. The same test can
; be run multiple times only serially, thus it can be specified multiple times,
; but each entry must be specified on a separate line - in this case, main
; log file from the 'entrypoint' file will contain concatenated logs from each
; test run.
; Required: yes
[recipe]\n" >"$RECIPE"
		tests=$(whale_getall_tests_for_dir "$TESTS_ROOT_DIR") || \
			return $?
		printf "$tests\n" >>"$RECIPE"
		eprintf "Recipe '$RECIPE' created,\nnow you can review it. "
		eprintf "Press any key to continue...\n"
		read -rs -n1 status
		nano "$RECIPE" >$(tty) <$(tty)

		# Does not allow user to change parameters 'plugin'
		# and 'tests_root_dir' inside the recipe file as they were
		# specified on command line already.
		sed -i "s|^plugin=.*$|plugin=$PLUGIN_DIR|" "$RECIPE"
		sed -i "s|^tests_root_dir=.*$|tests_root_dir=$TESTS_ROOT_DIR|" \
			"$RECIPE"
	fi

	# Loads global section parameters from the recipe file.
	whale_recipe_export_global_conf "$RECIPE" || return $?


	printf "[supervisord]
nodaemon=true
logfile=$SUPERVISOR_LOG
loglevel=info

[inet_http_server]
port=9001

[supervisorctl]
serverurl=http://localhost:9001/

[rpcinterface:supervisor]
supervisor.rpcinterface_factory = supervisor.rpcinterface:make_main_rpcinterface

[program:CONTROLLER]
command=/usr/bin/$TEST_CONTROLLER
directory=$TESTS_DIR
autostart=true
autorestart=false
startretries=0
startsecs=0
exitcodes=0
stderr_logfile=$TESTS_DIR/controller.log
stdout_logfile=$TESTS_DIR/controller.log\n" >"$temp_dir/supervisord.conf"
	printf "FROM $image\n" >"$temp_dir/Dockerfile"

	# Processes RECIPE file, adds tests into a Dockerfile.
	cat "$RECIPE" | grep "^\[recipe\]" >/dev/null
	if [ $? -ne 0 ]; then
		eprintf "Error: Recipe '$RECIPE' must contain section: recipe\n"
		return 1
	fi


	tests=""
	tests=$(whale_recipe_getall_recipes "$RECIPE") || return $?
	while read -r line; do
		# Removes redundant parallel tests.
		line=$(echo "$line" | xargs -n 1 | sort -u \
			| xargs)
		printf "$line\n" >>"$temp_dir/$CONTROLLER_CONF"
		for t in $line; do
			add_test $temp_dir $t || return $?
		done
	done <<<"$tests"

	commands=$(whale_recipe_getall_environment_commands "$RECIPE") || \
		return $?
	if [ ! -z "$commands" ]; then
		commands="RUN $commands"
	fi


	# Creates $TEST_CONTROLLER script for running tests inside a test
	# container.
	printf "#!/bin/bash\n
while read -r line; do
	supervisorctl -c $SUPERVISOR_CONF start \"\$line\"
	# wait for all tests in a batch to finish
	stat=\$(supervisorctl -c $SUPERVISOR_CONF status \"\$line\" | grep RUNNING)
	while [ ! -z \"\$stat\" ]; do
		sleep 1
		stat=\$(supervisorctl -c $SUPERVISOR_CONF status \"\$line\" | grep RUNNING)
	done
	echo \"\$line: exited\"
done </etc/$CONTROLLER_CONF
exit 0" >"$temp_dir/$TEST_CONTROLLER"


	all_pkgs=$(echo "$PLUGIN_REQ_PKGS $DEPS $DEBUG_PKGS" | xargs -n 1 \
		| sort -u | xargs)
	printf "RUN $PKG_INSTALL $all_pkgs; $TMP_FILES_CLEANUP\n
$commands\n
COPY supervisord.conf $SUPERVISOR_CONF
COPY $CONTROLLER_CONF /etc/$CONTROLLER_CONF
COPY $TEST_CONTROLLER /usr/bin/$TEST_CONTROLLER
RUN chmod a+x /usr/bin/$TEST_CONTROLLER\n
$2" >>"$temp_dir/Dockerfile"

	return 0
}
