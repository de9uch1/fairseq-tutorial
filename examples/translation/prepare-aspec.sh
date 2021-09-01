#!/bin/bash
# Copyright (c) Hiroyuki Deguchi
#
# This source code is licensed under the MIT license found in the
# LICENSE file in the root directory of this source tree.

function not_exists() {
    ! ( [[ -d $1 ]] || [[ -f $1 ]] )
}
function corpora_not_exists() {
    ! [[ -d $orig ]] || ! [[ -f $orig/train.$src ]]
}
function err() {
    printf "\033[1;31m!!! %s: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}
function log() {
    printf "\033[1;36m==> %s: %s\033[0m\n" "$(date +'%Y-%m-%d %H:%M:%S')" "$1" >&2
}

ASPEC_JE="${ASPEC_JE:-/path/to/ASPEC/ASPEC-JE}"      # replace with your correct path
if ! [[ -f "$ASPEC_JE/train/train-1.txt" ]]; then
    cat << __EOT__
\$ASPEC_JE ($ASPEC_JE) is not the correct path.
Please set 'ASPEC_JE' to the correct path.

Example:
    When ASPEC-JE is given with the following path,
    you must set ASPEC_JE as follows:

    $ export ASPEC_JE="/path/to/ASPEC/ASPEC-JE"

    /path/to/ASPEC/ASPEC-JE
    ├── dev
    │   └── dev.txt
    ├── devtest
    │   └── devtest.txt
    ├── README
    ├── README-j
    ├── test
    │   └── test.txt
    └── train
        ├── train-1.txt
        ├── train-2.txt
        └── train-3.txt
__EOT__
    exit 1
fi

src=ja
tgt=en
train_size=100000
OUTDIR=aspec_ja_en
prep=$OUTDIR
tmp=$prep/tmp
orig=$prep/orig
tools=$prep/tools
mkdir -p $prep $orig $tmp $tools

NUM_WORKERS=${NUM_WORKERS:-8}
BPE_TOKENS=8000

PARALLEL_SCRIPT="$tools/parallel"
PARALLEL_ARGS="--gnu --no-notice --pipe -j $NUM_WORKERS -k"
MOSES_SCRIPTS="$tools/mosesdecoder/scripts"
MOSES_TOKENIZER="$MOSES_SCRIPTS/tokenizer/tokenizer.perl"
KYTEA_TOKENIZER="$tools/kytea/bin/kytea"
NORM_PUNC="$MOSES_SCRIPTS/tokenizer/normalize-punctuation.perl"
Z2H="$(dirname $0)/z2h-utf8.pl"
CLEAN="$MOSES_SCRIPTS/training/clean-corpus-n.perl"
FASTBPE="$tools/fastBPE/fastbpe"

pushd "$tools" >/dev/null
if not_exists "$PARALLEL_SCRIPT" || \
        not_exists mosesdecoder || \
        not_exists "$KYTEA_TOKENIZER" || \
        not_exists "$FASTBPE"; then
    log "Some tools are not installed, start installing..."
    script_mode='install'
fi
if not_exists "$PARALLEL_SCRIPT"; then
    log 'Installing GNU parallel (for parallel execution)...'
    curl -sL -o parallel https://git.savannah.gnu.org/cgit/parallel.git/plain/src/parallel
    chmod +x parallel
    log 'Done.'
fi
if not_exists mosesdecoder; then
    log 'Installing Moses (for tokenization scripts)...'
    git clone https://github.com/moses-smt/mosesdecoder.git
    log 'Done.'
fi
if not_exists "$KYTEA_TOKENIZER"; then
    log 'Installing KyTea (for tokenization scripts)...'
    git clone https://github.com/neubig/kytea.git
    pushd kytea
    autoreconf -i
    ./configure --prefix=$(pwd)
    make -j4
    make install
    popd
    if not_exists "$KYTEA_TOKENIZER"; then
        err "KyTea not successfully installed, abort."
        exit 1
    fi
    log 'Done.'
fi
if not_exists "$FASTBPE"; then
    log 'Installing fastBPE repository (for BPE pre-processing)...'
    git clone https://github.com/glample/fastBPE.git
    pushd fastBPE
    g++ -std=c++11 -pthread -O3 fastBPE/main.cc -IfastBPE -o fastbpe
    popd
    if not_exists "$FASTBPE"; then
        err "fastBPE not successfully installed, abort."
        exit 1
    fi
    log 'Done.'
fi
if [[ $script_mode = 'install' ]]; then
    log '===> Installation is complete!'
fi
popd >/dev/null

cat "$ASPEC_JE/train/train-1.txt" | head -n $train_size > $orig/train.txt
cp "$ASPEC_JE/dev/dev.txt" $orig/dev.txt
cp "$ASPEC_JE/devtest/devtest.txt" $orig/devtest.txt
cp "$ASPEC_JE/test/test.txt" $orig/test.txt

set -e
log "Start preprocessing"
log "Extracting sentences..."
for split in dev devtest test; do
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[2], "\n";' < $orig/$split.txt > $orig/$split.ja
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/$split.txt > $orig/$split.en
done
for split in train; do
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[3], "\n";' < $orig/$split.txt > $orig/$split.ja
    perl -ne 'chomp; @a=split/ \|\|\| /; print $a[4], "\n";' < $orig/$split.txt > $orig/$split.en
done
log "Done."

log "Removing date expressions at EOS in Japanese in the training and development data to reduce noise..."
for split in train dev devtest; do
    mv $orig/$split.ja $orig/$split.ja.org
    cat $orig/$split.ja.org | perl -C -pe 'use utf8; s/(.)［[０-９．]+］$/$1/;' > $orig/$split.ja
    rm $orig/$split.ja.org
done
log "Done."

log "Tokenizing sentences in Japanese..."
for split in train dev devtest test; do
    cat $orig/$split.ja | \
        perl -C -pe 'use utf8; tr/\|[]/｜［］/; ' | \
        "$PARALLEL_SCRIPT" $PARALLEL_ARGS "$KYTEA_TOKENIZER" -out tok | \
        perl -C -pe 'use utf8; s/　/ /g;' | \
        perl -C -pe 'use utf8; s/^ +//; s/ +$//; s/ +/ /g;' \
             > $tmp/$split.ja
done
log "Done."

log "Tokenizing sentences in English..."
for split in train dev devtest test; do
    cat $orig/$split.en | \
        perl -C "$Z2H" | \
        perl -C "$NORM_PUNC" -l en | \
        perl -C "$MOSES_TOKENIZER" -threads $NUM_WORKERS -l en -a -no-escape 2>/dev/null | \
        perl -C -pe 'use utf8; s/^ +//; s/ +$//; s/ +/ /g;' \
             > $tmp/$split.en
done
log "Done."

log "Cleaning the corpus..."
perl "$CLEAN" -ratio 2.0 $tmp/train $src $tgt $tmp/train.clean 1 100
for l in $src $tgt; do
    mv $tmp/train.clean.$l $tmp/train.$l
done
log "Done."

log "Learn BPE on $tmp/train.$src, $tmp/train.$tgt..."
BPE_CODE=$prep/code
for l in $src $tgt; do
    train=train.$l
    "$FASTBPE" learnbpe $BPE_TOKENS $tmp/$train > $BPE_CODE.$l
    "$FASTBPE" applybpe $tmp/bpe$BPE_TOKENS.$train $tmp/$train $BPE_CODE.$l
    "$FASTBPE" getvocab $tmp/bpe$BPE_TOKENS.$train > $prep/vocab.$l
done
log "Done."

for l in $src $tgt; do
    BPE_VOCAB=$prep/vocab.$l
    for split in train dev devtest test; do
        f=$split.$l
        log "Apply BPE to $f..."
        "$FASTBPE" applybpe $prep/$f $tmp/$f $BPE_CODE.$l $prep/vocab.$l
        log "Done."
    done
done

log "Preprocessing is all complete!"
