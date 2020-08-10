#!/usr/bin/env bash
#
# This script allows to run give commands inside a docker container.
# The first parameter needs to specify the location of the Dockerfile that should
# be used to construct the container.

set -e

# Print usage
usage ()
{
    cat << EOF
  This script allows to run a command with the permissions of the current user
  in the current directory, but wrapped in a docker container. The execution
  will start in the current directory as a working directory, and this directory
  is mounted inside the container as well, so that all sub-directories are
  accessible as well. The execution will be performed with the user ID and group
  IDs of the calling users. This allows to easily consume files that have been
  written while executing inside the container.

  The container can be specified as either a dockerfile, or a docker image.

  Usage:

  $0 [options] dockertarget command [command arguments]

     dockertarget .... path to Dockerfile, directory that contains a file called
                       Dockerfile
     command ......... command to be executed

     command args .... arguments passed to command when being executed in the
                       container

     options:
      -e KEY=VALUE ... forward environment variables to the containers, so that
                       they are visible during the execution in the container
      -s ............. Use "sudo" for all calls to docker

EOF
}

declare -a DOCKER_ENVIRONMENT
SUDO=

# handle CLI options
while getopts "e:hs" opt
do
    case $opt in
        e)
            DOCKER_ENVIRONMENT+=("-e" "$OPTARG")
            ;;
        h)
            usage
            exit 0
            ;;
        s)
            SUDO="sudo"
            ;;
        \?)
            echo "" 1>&2
            usage 1>&2
            exit 1
            ;;
    esac
done
shift $(( OPTIND - 1 ))

# check expected parameters
if [ "$#" -le 1 ]
then
    echo -e "Did not find a docker target and command to be executed, aborting\n"

    usage
    exit 1
fi

# get location of docker file
docker_file_or_dir_or_image="$1"
shift

containerid=""

# by default, assume we received a directory
declare docker_build_target=("$docker_file_or_dir_or_image")

# is the given parameter a file?
if [ -f "$docker_file_or_dir_or_image" ]
then
    # tell docker build to use the file, instead of the dir
    docker_file_dir="$(dirname "$docker_file_or_dir_or_image")"
    docker_build_target=("-f" "$docker_file_or_dir_or_image" "$docker_file_dir")
elif [ ! -d "$docker_file_or_dir_or_image" ]
then
    echo "error: cannot find specified directory $docker_file_or_dir_or_image, abort"
    exit 1
fi

# (re) build fresh container
containerid=$($SUDO docker build -q ${docker_build_target[@]})


DOCKER_ARGS=("-w" "$PWD" "-v" "$PWD:$PWD")
if [ "${#DOCKER_ENVIRONMENT[@]}" -gt 0 ]
then
	DOCKER_ARGS+=(${DOCKER_ENVIRONMENT[@]})
fi

# Forward Coverity environment variables
# (make sure the while loop is not executed in a sub-shell)
while IFS='' read -r line
do
	[ -z "$line" ] || DOCKER_ARGS+=("-e${line}")
done <<< "$(printenv | grep "COVERITY" || true)"

# run the rest of the provided command inside the docker container
#  * run as current user
#  * use the current directory as work directory
#  * forward the home directory
#  * cleanup once we're done
$SUDO docker run -t \
     --rm \
     --user $(id -u) $(printf -- "--group-add=%q " $(id -G)) \
     --tmpfs /tmp --tmpfs /var/tmp \
     "${DOCKER_ARGS[@]}" \
     "$containerid" "$@"
