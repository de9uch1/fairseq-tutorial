#!/bin/bash
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

function not_exists() {
    ! ( [[ -d $1 ]] || [[ -f $1 ]] )
}
function err() {
    printf "\033[1;31m!!! %s: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}
function log() {
    printf "\033[1;36m==> %s: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}
function usage() {
    cat << __EOT__ >&2
Usage: $(basename $0) [ ja | en | zh ] TEST_FILE

Arguments:
    [ ja | en | zh ]     Language code
    TEST_FILE            Test file path
__EOT__
    exit 1
}

TEST_FILE="$(readlink -f $2)"
if [[ -z "$TEST_FILE" ]] || ! [[ -f "$TEST_FILE" ]]; then
    echo "Reference file not found." >&2
    usage "TEST_FILE '$TEST_FILE' not found."
fi
fname="$(basename $TEST_FILE)"
test_set="$(basename $fname .txt)"
CORPUS="$(basename $(readlink -f $(dirname $TEST_FILE)/..))"

REF_DIR="$(dirname $0)/aspec_ja_en/ref"
prep=$REF_DIR/$CORPUS
orig=$prep/orig
mkdir -p "$prep" "$orig" "$prep/tools"

tools="$(readlink -f $prep/tools)"

if [[ $# -ne 2 ]] || \
       ([[ $1 != ja ]] && [[ $1 != en ]] && [[ $1 != zh ]]) || \
       ! [[ -f "$2" ]]; then
    usage
fi
tgt=$1

MOSES_SCRIPTS="$tools/mosesdecoder-2.1.1/scripts"
MOSES_TOKENIZER="$MOSES_SCRIPTS/tokenizer/tokenizer.perl"
KYTEA_ROOT="$tools/kytea-0.4.6"
KYTEA_TOKENIZER="$KYTEA_ROOT/bin/kytea"
KYTEA_MODELNAME_JA=jp-0.4.2-utf8-1.mod
KYTEA_MODELNAME_ZH=msr-0.4.0-1.mod
KYTEA_MODEL_JA="$KYTEA_ROOT/$KYTEA_MODELNAME_JA"
KYTEA_MODEL_ZH="$KYTEA_ROOT/$KYTEA_MODELNAME_ZH"
WAT_SCRIPTS="$tools/WAT-scripts"

# for evaluation
MOSES_BLEU="$MOSES_SCRIPTS/generic/multi-bleu.perl"
RIBES_DIR="$tools/RIBES-1.02.4"
RIBES_SCRIPT="$RIBES_DIR/RIBES.py"

pushd "$tools" >/dev/null
if not_exists "$MOSES_SCRIPTS"; then
    log "Cloning Moses github repository (for tokenization and evaluation)..."
    git clone https://github.com/moses-smt/mosesdecoder.git \
        -b RELEASE-2.1.1 \
        mosesdecoder-2.1.1
fi >&2
if ([[ $tgt = "ja" ]] || [[ $tgt = "zh" ]]) && not_exists "$KYTEA_ROOT"; then
    log "Downloading Kytea source code (for tokenization)..."
    curl http://www.phontron.com/kytea/download/kytea-0.4.6.tar.gz | tar xzf -
fi >&2
if not_exists "$WAT_SCRIPTS"; then
    log "Cloning WAT-scripts github repository (for preprocess)..."
    git clone https://github.com/hassyGO/WAT-scripts.git
fi >&2
if not_exists "$RIBES_SCRIPT"; then
    log "Downloading RIBES script (for evaluation)..."
    curl "http://www.kecl.ntt.co.jp/icl/lirg/ribes/package/RIBES-1.02.4.tar.gz" | tar xz
fi >&2
if ([[ $tgt = "ja" ]] || [[ $tgt = "zh" ]]) && not_exists "$KYTEA_TOKENIZER"; then
    pushd "$KYTEA_ROOT"
    ./configure --prefix=$(pwd)
    make clean
    make -j4
    make install
    popd
    if not_exists "$KYTEA_TOKENIZER"; then
        err "kytea not successfully installed, abort."
        exit 1
    fi
fi >&2
if [[ $tgt = "ja" ]] && not_exists "$KYTEA_MODEL_JA"; then
    pushd $(dirname "$KYTEA_MODEL_JA")
    curl -O "http://www.phontron.com/kytea/download/model/$KYTEA_MODELNAME_JA.gz"
    gzip -d $KYTEA_MODELNAME_JA.gz
    popd
    if not_exists "$KYTEA_MODEL_JA"; then
        err "kytea model not successfully downloaded, abort."
        exit 1
    fi
fi >&2
if [[ $tgt = "zh" ]] && not_exists "$KYTEA_MODEL_ZH"; then
    pushd $(dirname "$KYTEA_MODEL_ZH")
    curl -O "http://www.phontron.com/kytea/download/model/$KYTEA_MODELNAME_ZH.gz"
    gzip -d $KYTEA_MODELNAME_ZH.gz
    popd
    if not_exists "$KYTEA_MODEL_ZH"; then
        err "kytea model not successfully downloaded, abort."
        exit 1
    fi
fi >&2
popd >/dev/null

function extract() {
    mkdir -p $prep $orig
    cp $TEST_FILE $orig/$fname

    if [[ $CORPUS = "ASPEC-JE" ]]; then
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$fname > $orig/$test_set.ja
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/$fname > $orig/$test_set.en
    elif [[ $CORPUS = "ASPEC-JC" ]]; then
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[1], "\n";' < $orig/$fname > $orig/$test_set.ja
        perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$fname > $orig/$test_set.zh
    fi
}

function tokenize_ja() {
    cat - | \
        perl -C -pe 'use utf8; s/(.)［[０-９．]+］$/${1}/;' | \
        sh "$WAT_SCRIPTS/remove-space.sh" | \
        perl -C "$WAT_SCRIPTS/h2z-utf8-without-space.pl" | \
        "$KYTEA_TOKENIZER" -model "$KYTEA_MODEL_JA" -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;' | \
        perl -C -pe 'use utf8; while(s/([０-９]) ([０-９])/$1$2/g){} s/([０-９]) (．) ([０-９])/$1$2$3/g; while(s/([Ａ-Ｚ]) ([Ａ-Ｚａ-ｚ])/$1$2/g){} while(s/([ａ-ｚ]) ([ａ-ｚ])/$1$2/g){}'
}

function tokenize_en() {
    perl -C "$(dirname $0)/z2h-utf8.pl" | \
        perl -C "$MOSES_TOKENIZER" -l en -threads 8
}

function tokenize_zh() {
    cat - | \
        sh "$WAT_SCRIPTS/remove-space.sh" | \
        perl -C "$WAT_SCRIPTS/h2z-utf8-without-space.pl" | \
        "$KYTEA_TOKENIZER" -model "$KYTEA_MODEL_ZH" -out tok | \
        perl -C -pe 's/^ +//; s/ +$//; s/ +/ /g;'
}

function tokenize() {
    tokenize_$1 2>/dev/null
}

function eval_bleu() {
    "$MOSES_BLEU" $prep/$test_set.$tgt < $1 2>/dev/null
}

function eval_ribes() {
    python3 "$RIBES_SCRIPT" -c -r $prep/$test_set.$tgt $1 2>/dev/null
}

function clean_tmpdir() {
    [[ -d $TMPDIR ]] && rm -rf $TMPDIR
}

if ! [[ -f $prep/$test_set.$tgt ]]; then
    extract >/dev/null 2>&1
    cat $orig/$test_set.$tgt | \
        tokenize $tgt \
                 >$prep/$test_set.$tgt
fi

TMPDIR=$(mktemp -d)
trap clean_tmpdir EXIT
trap "clean_tmpdir; exit 1" INT PIPE TERM
sysout=$TMPDIR/sysout.tmp

cat - | tokenize $tgt > $sysout
eval_bleu $sysout
eval_ribes $sysout
