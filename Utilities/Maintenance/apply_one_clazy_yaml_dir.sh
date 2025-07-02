#!/bin/bash
#
# A script to assist with applying found fixes
# NOTE: This is a good starting point, but is almost certainly not complete!
#       compiler errors may be present, check manually with care.
#

SCRIPT_DIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
export SRC_DIR="$(dirname $(dirname ${SCRIPT_DIR}))"
export BLD_DIR=$(dirname ${SRC_DIR})/Qt5clazySlicer-build
export INNER_BLD_DIR=${BLD_DIR}/Slicer-build

echo "
SRC_DIR="$(dirname $(dirname ${SCRIPT_DIR}))"
BLD_DIR=$(dirname ${SRC_DIR})/Qt5clazySlicer-build
INNER_BLD_DIR=${BLD_DIR}/Slicer-build
"

usage() {
  echo "USAGE: $0 <clazy_yaml_file>"
  echo ""
  echo "find ${SRC_DIR} ${INNER_BLD_DIR} -name \"*.clazy.yaml\" -exec $(realpath ${SCRIPT_DIR}/$0) {} \\;"
  exit -1
}

cd ${INNER_BLD_DIR}
clazy_yaml_file=$1
if [ $# -ne 1 ];then
  usage
fi
if [ ! -f ${clazy_yaml_file} ]; then
  usage
fi

precommit_bin=$(which pre-commit)
if [ ! -f ${precommit_bin} ];then
  echo "required pre-commit not found:  consider a possible solution like the following"
  echo "python3 -m venv /tmp/venv"
  echo "source /tmp/venv"
  echo "pip install pre-commit"
fi
clazy_yaml_dir=$(dirname ${clazy_yaml_file})

# Convert the yaml files to standard gcc errfmt files for
# easier corrections via `vim -q /tmp/errmt.err`
error_file=/tmp/errfmt.err
for clazy_yaml_file in ${clazy_yaml_dir}/*.clazy.yaml; do
  # Only include errors/warnings from this source tree in them
  ${SCRIPT_DIR}/yaml_to_gcc_fmt.py ${clazy_yaml_file} | grep ${SRC_DIR} >> ${error_file}
done
sort -u ${error_file} > ${error_file}.tmp
mv ${error_file}.tmp ${error_file}

clang-apply-replacements-19 \
  --format                  \
  --style=file              \
  ${clazy_yaml_dir}

cd ${SRC_DIR}
for changed_file in $(git diff --name-only); do
  git add ${changed_file}
done

pre-commit run -a
message_file=/tmp/commit_msg_clazy_$(date +%Y%m%d.%H%M%S)
cat > ${message_file} << EOF
ENH: Update to support Qt6 using clazy auto-fixes

$(grep --no-filename  "\<Message: " ${clazy_yaml_dir}/*.clazy.yaml |sed 's/  */ /g' )
EOF


for done_file in ${clazy_yaml_dir}/*.clazy.yaml; do
  mv ${done_file} ${done_file//.yaml/.doneyaml}
done

if cmake --build ${INNER_BLD_DIR}; then
  git commit -e -F ${message_file}
else
  echo "============================================================="
  echo "Fix compiler errors, then run git commit -e -F ${message_file}"
fi
echo "=Useful commands============================================================"
echo vim -q ${error_file}
echo "find ${SRC_DIR} ${INNER_BLD_DIR} -name \"*.clazy.yaml\""
echo "find ${SRC_DIR} ${INNER_BLD_DIR} \"*.clazy.doneyaml\" -delete"
