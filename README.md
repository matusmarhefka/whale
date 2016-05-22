whale
=====

Whale is the framework for testing software running in Docker containers.
The framework consists of the core module which provides basic functionality
and it is designed to be extensible with an additional custom code in form
of a plugin.

![picture alt](https://github.com/matusmarhefka/whale/blob/master/doc/arch.png)

Requirements
------------
    bash, coreutils, grep, sed,
    gawk, nano, tar, gzip
    findutils (find, xargs),
    util-linux (column, flock),
    procps-ng (ps).

On Fedora:

    $ dnf install -y bash coreutils grep sed gawk nano findutils util-linux procps-ng tar gzip

Installation
------------
    $ git clone https://github.com/matusmarhefka/whale.git
    $ cd whale/
    $ ./whale help
    
Usage
-----
First of all, the framework needs to be configured, which includes setting
a plugin that will be used for working with Docker containers, and generating
`test.ini` configuration files for each test in the tests root directory.
The `make-conf` command can be used for this purpose:

    $ ./whale make-conf examples/tests/plugin-default/Dummy plugins/default

The framework uses recipe configuration files which provide information about:
* a path to the directory with tests,
* prameters for testing,
* additional commands to extend the testing environment inside a container,
* what tests from the directory with tests should be executed inside
  a container.

Recipe file is created automatically by the framework, if the one specified
on the command-line doesn't exist and user is allowed to edit it before saving.
Each test inside the tests root directory (`examples/tests/plugin-default/Dummy`)
must be placed in its own subdirectory and must provide its own `test.ini`
configuration file. In this example, Fedora image is used as a base image
for creating testing environment:

    $ image=$(./whale setup fedora fedora_recipe.ini examples/tests/plugin-default/Dummy)

When testing environment is prepared inside the `$image` image, testing process
can be started inside a test container using the `run` framework command.
The `./fedora_cont_logs` directory will be created on the host filesystem
and tests specified in the recipe configuration file will be copied into this
directory. Then, this directory will be mounted into the test container:

    $ cont=$(./whale run $image ./fedora_cont_logs)

Progress and status of testing inside the `$cont` container can be viewed
with the `status` framework command:

    $ ./whale status $cont

When testing is finished, all the logs can be found in the `./fedora_cont_logs`
directory.

To print information about built images and running containers:

    $ ./whale info

Framework commands workflow
---------------------------
![picture alt](https://github.com/matusmarhefka/whale/blob/master/doc/workflow.png)
