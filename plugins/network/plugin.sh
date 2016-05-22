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
# Network plugin is intended for testing the multi-container application
# on single-host system use cases. Firstly, the plugin prepares the testing
# environment by building a test image. Secondly, the built test image is
# started, forming a test container and tests are deployed into that container
# by the volume mount. Then, the manager software prepared inside the test
# container (also referred to as the controller) is executed, it runs
# the pre-configured tests and it can report the progress and status of testing
# when requested by the framework core module running on the host system.
#
# Network plugin differs from the default plugin in the following:
# 1. The test image built in the setup phase is run in a way that it provides
#    the docker binary from the host filesystem to the test container, meaning
#    that from the test container it is possible to access other containers
#    running on the host system.
# 2. An application container which will be the target of testing needs to be
#    provided (it can be part of the multi-container application): the provided
#    application container needs to be already running.
# 3. The test container provides environment variables AC_ADDR and AC_PORT
#    referring to the application container.
#
#===============================================================================

# Temporary directory for building Docker images. Should be removed after build
# process finishes. Location of this temporary directory should be in /tmp.
TEMP_DIR=""

# Name of a test image only set during the setup phase.
TEST_IMAGE_NAME=""

PLUGIN_REQ_PKGS="supervisor bash coreutils grep wget"
TESTS_DIR="/tests"
SUPERVISOR_CONF="/etc/supervisord.conf"
SUPERVISOR_LOG="$TESTS_DIR/supervisord.log"
TEST_CONTROLLER="controller.sh"
CONTROLLER_CONF="controller.conf"
#===============================================================================

# Plugin specific trap handling function for setup command.
plugin_trap_cleanup() {
	rv=$?
	if [ -d $TEMP_DIR ]; then
		rm -rf $TEMP_DIR
	fi

	unlock 2>/dev/null

	# Removes failed image builds and intermediate containers; only sleeps
	# if $rv is not 0 (this means either SIGHUP, SIGINT or SIGTERM was
	# delivered before).
	if [ $rv -ne 0 ]; then
		docker rmi -f $TEST_IMAGE_NAME >/dev/null 2>&1
		sleep 1
	fi
	docker rmi -f $(docker images | grep "^<none>" \
		| awk '{print $3}') >/dev/null 2>&1
	docker rm -f $(docker ps -aq -f exited=137) >/dev/null 2>&1

	# Restores tty flags.
	stty $TTY_FLAGS 2>/dev/null

	exit $rv
}

#===============================================================================

# Prints plugin specific help.
plugin_print_help() {
	printf "  setup DIR|IMAGE RECIPE.ini TESTS_ROOT_DIR
                        -- Either builds an image if DIR is a directory (DIR
                           must contain Dockerfile and all the required files
                           to build a Docker image with software you would like
                           to test) or uses an existing IMAGE which must be
                           available in the local Docker repository ('docker
                           images' command). Then adds configuration for all
                           the tests (stored in the TESTS_ROOT_DIR directory)
                           which are specified in the RECIPE configuration file
                           into that image. If the RECIPE file does not exist
                           it will be created and user will have the ability
                           to edit it before the build process starts.
  run APP_CONTAINER IMAGE RESULTS_DIR
                        -- Runs a new test container based on the image
                           IMAGE (which contains the tests configuration and
                           was built by 'setup' command), creates a directory
                           RESULTS_DIR, copies all the tests configured for
                           the IMAGE into it and mounts it into the new test
                           container. Logs from testing will also be placed
                           into the RESULTS_DIR directory. APP_CONTAINER is
                           a running container with application which will be
                           tested through network from the test container.
                           The test container provides AC_ADDR and AC_PORT
                           environment variables referring to the APP_CONTAINER.
  status CONTAINER      -- Shows the status of testing for a specified
                           container: returns 2 if testing is still in progress,
                           0 if all the tests exited with 0 code, 124 if one or
                           more tests exited with non 0 code, or 1 on internal
                           error.\n"
}
#===============================================================================

# Builds base image if a directory is specified as the first argument or uses
# an existing image if it is specified as the first argument instead
# of a directory. Then builds a test image from a base image, placing tests
# configuration on top of it according to a RECIPE file (the second argument).
# All built images are stored into the $WHALE_CONF file.
# Returns 0 on success, non 0 on error.
plugin_setup() {
	local image cmd size
	if [ $# -gt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ ! -d "$3" ]; then
		eprintf "Usage: setup DIR|IMAGE RECIPE.ini TESTS_ROOT_DIR\n"
		return 1
	fi
	trap plugin_trap_cleanup EXIT SIGHUP SIGINT SIGTERM || return $?
	eprintf "Plugin: $PLUGIN_DIR\n"

	TESTS_ROOT_DIR=$(cd $3; pwd)
	RECIPE="$(cd $(dirname $2); pwd)/$(basename $2)"

	if [ -d "$1" ]; then
		image=$(basename "$1")
		docker build --rm -t "$image" "$1" 1>&2 || return $?
	else
		image=$1
		docker images | grep "$image" >/dev/null
		if [ $? -ne 0 ]; then
			docker pull "$image" 1>&2
			if [ $? -ne 0 ]; then
				eprintf "Error: Image not found: $image\n"
				return 1
			fi
		fi
	fi

	# Checks if $WHALE_CONF already contains $image.
	size=$(get_docker_image_size "$image") || return $?
	lock || return $?
	if [ -s "$WHALE_CONF" ]; then
		cat "$WHALE_CONF" | grep "$image" >/dev/null
		if [ $? -ne 0 ]; then
			file_insert_first_line "$image $size -" "$WHALE_CONF" || return $?
		fi
	else
		printf "$image $size -" >"$WHALE_CONF"
	fi

	# Checks if $WHALE_CONF already contains RECIPE.
	cat "$WHALE_CONF" | grep "$RECIPE" >/dev/null
	if [ $? -eq 0 ]; then
		eprintf "Image for recipe '$RECIPE' already exists:\n"
		cat "$WHALE_CONF" | grep "$RECIPE"
		unlock || return $?
		return 0
	fi
	unlock || return $?

	# Checks CMD for base images. If there is no CMD, uses CMD ["bin/bash"],
	# otherwise uses the default CMD.
	cmd=$(docker inspect -f '{{ .ContainerConfig.Cmd }}' $image \
		| sed 's/.*\(CMD.*"]\).*/\1/')
	if [[ $cmd != "CMD"*"["*"]" ]]; then
		cmd="CMD [ \"/bin/bash\" ]"
	fi
	TEMP_DIR=$(cmd mktemp -d "/tmp/$ME.XXXXXX") || return $?
	plugin_create_dockerfile "$image" "$cmd" "$TEMP_DIR" || return $?

	# Every test image name must differ.
	lock || return $?
	TEST_IMAGE_NAME="w_network/$image/$(date +%Y%m%d_%H%M%S)"
	sleep 1
	unlock || return $?
	docker build --rm -t $TEST_IMAGE_NAME $TEMP_DIR 1>&2 || return $?
	eprintf "Test image created: "
	printf "$TEST_IMAGE_NAME\n"
	rm -rf $TEMP_DIR

	size=$(get_docker_image_size "$TEST_IMAGE_NAME") || return $?
	lock || return $?
	file_insert_first_line "$TEST_IMAGE_NAME $size $RECIPE" "$WHALE_CONF" \
		|| return $?
	unlock || return $?

	return 0
}
#===============================================================================

# Checks if the image specified as the first argument is in the $WHALE_CONF
# file. If not, returns error, otherwise function also checks the image's recipe
# file to find out which plugin it uses. If $ME is not configured with the same
# plugin as the image is, returns error.
# Copies all the tests specified in the [recipe] section in the recipe file
# into a new directory on the host specified as the third argument ($3). Runs
# a new test container from the specified image (the second argument) and mounts
# tests from the host directory ($3) into the $TESTS_DIR directory in the test
# container. Then starts the test controller (supervisor) inside that test
# container. Tests in the test container can also use docker binary from
# the host filesystem, which is mounted in /usr/bin/docker.
# Returns 0 on success, 1 on error.
plugin_run() {
	local section="" results_dir recipe cont cmd addr port rv
	if [ $# -gt 3 ] || [ -z "$1" ] || [ -z "$2" ] || [ -z "$3" ]; then
		eprintf "Usage: run APP_CONTAINER IMAGE RESULTS_DIR\n"
		return 1
	fi
	eprintf "Plugin: $PLUGIN_DIR\n"

	recipe=$(whale_get_image_recipe "$2") || return $?
	if [ "$recipe" == "-" ]; then
		eprintf "Error: Image is a base image and has no recipe: $2\n"
		return 1
	fi

	# Checks CMD for base images. If there is no CMD, uses "bin/bash",
	# otherwise uses the default CMD.
	cmd=$(docker inspect -f '{{ .ContainerConfig.Cmd }}' $2 \
		| sed 's/.*\(CMD.*"]\).*/\1/')
	if [[ $cmd != "CMD"*"["*"]" ]]; then
		cmd="/bin/bash"
	else
		# Uses the default CMD.
		cmd=""
	fi

	# Gets the IP address and port of an application container.
	docker ps -a | grep "$1" >/dev/null
	if [ $? -ne 0 ]; then
		eprintf "Error: No such running container: $1\n"
		return 1
	fi
	addr=$(docker inspect -f '{{ .NetworkSettings.IPAddress }}' $1 \
		2>/dev/null)
	port=$(docker inspect -f '{{range $p, $conf := .NetworkSettings.Ports}}{{(index $conf 0).HostPort}}{{end}}' $1 2>/dev/null)
	if [ -z "$addr" ] || [ -z "$port" ]; then
		eprintf "Error: Application container does not export IP "
		eprintf "address or port: $1\n"
		return 1
	fi
	eprintf "$1 exports [$addr:$port]\n"

	# Loads global section parameters from the recipe file.
	whale_recipe_export_global_conf "$recipe" || return $?
	eprintf "Recipe: $recipe\n"

	# Checks if plugin configured in $WHALE_CONF is the same
	# as in the recipe file ($PLUGIN): if not, error.
	if [ "$PLUGIN_DIR" != "$PLUGIN" ]; then
		eprintf "Error: Image uses plugin '$PLUGIN'\n"
		eprintf "which differs from the plugin in use.\n"
		eprintf "To change plugin to the plugin of the image\n"
		eprintf "run command: 'make-conf $PLUGIN'\n"
		return 1
	fi

	results_dir="$(cd $(dirname $3); pwd)/$(basename $3)"
	mkdir "$results_dir" || return $?

	# Gets locations of tests inside the image $2 from recipe section
	# from recipe.ini file and copies them into the $results_dir.
	while read -r line; do
		line=$(echo "$line" |  sed 's/;.*$//')
		if [[ $line == "[recipe]"* ]]; then
			section="recipe"
			continue
		elif [ -z "$line" ]; then
			continue
		fi

		if [ "$section" == "recipe" ]; then
			for t in $line; do
				mkdir -p "$results_dir/$(dirname $t)"; rv=$?
				cp -rp "$TESTS_ROOT_DIR/$t" \
					"$results_dir/$(dirname $t)"
				rv=$(($rv + $?))
				if [ $rv -ne 0 ]; then
					rm -rf $results_dir
					return 1
				fi
			done
		fi
	done <"$recipe"

	# Runs the specified IMAGE providing docker binary to the test container
	# and also runs supervisor.
	cont=$(docker run -dt -v /var/run/docker.sock:/var/run/docker.sock \
		-v $(which docker):/usr/bin/docker \
		-v /etc/localtime:/etc/localtime:ro \
		-v /lib64/libltdl.so.7:/lib64/libltdl.so.7:ro \
		-l "$WHALE_LABEL" -l "$WHALE_IMG_LABEL=$2" \
		-e AC_ADDR="$addr" -e AC_PORT="$port" \
		-v $results_dir:$TESTS_DIR:z \
		$DOCKER_RUN_OPTIONS "$2" $cmd) || return $?
	cont="${cont:0:12}"
	docker exec -dt "$cont" /usr/bin/supervisord -c /etc/supervisord.conf
	printf "$cont\n"

	return 0
}
#===============================================================================

# Shows the status of testing inside a container provided as the first argument.
# Returns 2 if testing is still in progress, 0 if all the tests exited with 0
# code, 124 if one or more tests exited with non 0 code, or 1 on error.
plugin_status() {
	local output output2 status supervisor_log cmd_exec
	if [ $# -gt 1 ] || [ -z "$1" ]; then
		eprintf "Usage: status CONTAINER\n"
		return 1
	fi
	eprintf "Plugin: $PLUGIN_DIR\n"

	whale_check_cont_plugin $1 >/dev/null || return $?
	cmd_exec=$(echo "docker inspect --format '{{range .Mounts}}{{if eq .Destination \"$TESTS_DIR\"}}{{.Source}}{{end}}{{end}}' $1")
	supervisor_log=$(eval $cmd_exec)
	supervisor_log="$supervisor_log/$(basename $SUPERVISOR_LOG)"

	output=$(docker exec -t $1 supervisorctl -c $SUPERVISOR_CONF status)
	echo "$output" | grep "CONTROLLER.*EXITED" >/dev/null
	status=$?
	printf "$output\n\nFailed tests:\n"

	# Checks if some test has unexpected exit
	# status, if yes, prints entry from the log.
	output2=$(cat $supervisor_log | \
		grep "exit status [0-9]\+; not expected")
	test_stat=$?
	if [ $test_stat -eq 0 ]; then
		printf "$output2\n"
	fi

	if [ $status -ne 0 ]; then
		status=2
	else
		# If CONTROLLER exited, return status code 124.
		if [ $test_stat -eq 0 ]; then
			status=124
		fi
	fi

	return $status
}
#===============================================================================
