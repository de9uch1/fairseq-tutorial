#!/bin/bash
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

tools="$(dirname $0)/aspec_ja_en/tools"
MOSES_SCRIPTS="$tools/mosesdecoder/scripts"
MOSES_DETOKENIZER="$MOSES_SCRIPTS/tokenizer/detokenizer.perl"

function usage() {
    cat << __EOT__ >&2
Usage: $(basename $0) [ ja | en ]

Arguments:
    [ ja | en ]     Language code
__EOT__
    exit 1
}

function detokenize_ja() {
    perl -C -pe 's/([^Ａ-Ｚａ-ｚA-Za-z]) +/${1}/g; s/ +([^Ａ-Ｚａ-ｚA-Za-z])/${1}/g;'
}

function detokenize_en() {
    perl -C "$MOSES_DETOKENIZER" -l en -threads 8
}

function main() {
    if [[ $# -ne 1 ]] || ([[ $1 != ja ]] && [[ $1 != en ]]); then
        usage
    fi

    detokenize_$1
}

main "$@"
