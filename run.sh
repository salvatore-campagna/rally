#!/usr/bin/env bash

##########################################################################################
#
# Internal helper script to actually run either Rally or Rally daemon.
#
# Do not invoke directly but rather use the `rally` and `rallyd` scripts.
#
##########################################################################################

readonly BINARY_NAME="${__RALLY_INTERNAL_BINARY_NAME}"
readonly HUMAN_NAME="${__RALLY_INTERNAL_HUMAN_NAME}"

# Attempt to update Rally itself by default but allow user to skip it.
SELF_UPDATE=YES
# Assume that the "main remote" is called "origin"
REMOTE="origin"

# Check for parameters that are intended for this script. Note that they only work if they're specified at the beginning (due to how
# the shell builtin `shift` works. We could make it work for arbitrary positions but that's not worth the complexity for such an
# edge case).
for i in "$@"
do
case ${i} in
    --update-from-remote=*)
    REMOTE="${i#*=}"
    shift # past argument=value
    ;;
    --skip-update)
    SELF_UPDATE=NO
    shift # past argument with no value
    ;;
    # inspect Rally's command line options and skip update also if the user has specified --offline.
    #
    # Note that we do NOT consume this option as it needs to be passed to Rally.
    --offline)
    SELF_UPDATE=NO
    # DO NOT CONSUME!!
    ;;
    # Do not consume unknown parameters; they should still be passed to the actual Rally script
    #*)
esac
done

if [ ${SELF_UPDATE} == YES ]
then
    # see http://unix.stackexchange.com/a/155077
    if output=$(git status --porcelain) && [ -z "$output" ] && on_master=$(git rev-parse --abbrev-ref HEAD) && [ "$on_master" == "master" ]
    then
      # Working directory clean -> we assume this is a user that is not actively developing Rally and just upgrade it every time it is invoked
      set +e
      # this will fail if the user is offline
      git fetch ${REMOTE} --quiet >/dev/null 2>&1
      exit_code=$?
      set -e
      if [ ${exit_code} == 0 ]
      then
        echo "Auto-updating Rally from ${REMOTE}"
        git rebase ${REMOTE}/master --quiet
        # if we're running in a virtualenv then the --user prefix is not defined (and makes no sense)
        # While we could also check via the presence of `VIRTUAL_ENV` this is a bit more reliable.
        python3 -c 'import sys; print(sys.real_prefix)' 2>/dev/null && IN_VIRTUALENV=1 || IN_VIRTUALENV=0
        if [ ${IN_VIRTUALENV} == 0 ]
        then
            python3 setup.py -q develop --user
        else
            python3 setup.py -q develop
        fi
      #else
      # offline - skipping update
      fi
    # else
      # Uncommitted changes - don't upgrade, just run
    fi
#else -> No self update
fi

popd >/dev/null 2>&1

# write the actor system's log file to a well-known location (but let the user override it with the same env variable)
export THESPLOG_FILE="${THESPLOG_FILE:-${HOME}/.rally/logs/actor-system-internal.log}"
# this value is in bytes, the default is 50kB. We increase it to 200kiB.
export THESPLOG_FILE_MAXSIZE=${THESPLOG_FILE_MAXSIZE:-204800}

# Provide a consistent binary name to the user and hide the fact that we call another binary under the hood.
export RALLY_ALTERNATIVE_BINARY_NAME=$(basename "$0")
RALLY_ROOT=$(python3 -c "import site; print(site.USER_BASE)")
RALLY_BIN=${RALLY_ROOT}/bin/${BINARY_NAME}
if [ -x "$RALLY_BIN" ]
then
    ${RALLY_BIN} "$@"
else
    echo "Cannot execute ${HUMAN_NAME} in ${RALLY_BIN}."
fi