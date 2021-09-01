This is a tutorial document of `pytorch/fairseq <https://github.com/pytorch/fairseq>`_.

----

.. contents:: **Table of Contents**

0. Preface
==========

-  The current stable version of Fairseq is v0.x, but v1.x will be released soon.
   The specification changes significantly between v0.x and v1.x. This
   document is based on v1.x, assuming that you are just starting your
   research.

   ================== ================================== =======================
            \                   v0.x                               v1.x
   ================== ================================== =======================
   Configuration      ``args: ArgumentParser.Namespace`` ``cfg: OmegaConf``
   Add options        ``add_args(self, args)``           ``@dataclass``
   Training command   ``fairseq-train```                 ``fairseq-hydra-train``
   ================== ================================== =======================

-  This document assumes that you understand virtual environments (e.g.,
   pipenv, poetry, venv, etc.) and CUDA_VISIBLE_DEVICES.

1. Installation
===============

I recommend to install from the source in a virtual environment.

.. code:: bash

   git clone https://github.com/pytorch/fairseq
   cd fairseq
   pip install --editable ./

If you want faster training, install NVIDIA’s apex library.

.. code:: bash

   git clone https://github.com/NVIDIA/apex
   cd apex
   pip install -v --no-cache-dir --global-option="--cpp_ext" --global-option="--cuda_ext" \
     --global-option="--deprecated_fused_adam" --global-option="--xentropy" \
     --global-option="--fast_multihead_attn" ./

2. Training a Transformer NMT model
===================================

-  https://github.com/de9uch1/fairseq-tutorial/tree/master/examples/translation

3. Code walk
============

Commands
--------

-  ``fairseq-preprocess`` : Build vocabularies and binarize training
   data.
-  ``fairseq-train`` : Train a new model
-  ``fairseq-hydra-train`` : Train a new model w/ hydra
-  ``fairseq-generate`` : Generate sequences (e.g., translation,
   summary, POS tag etc.)
-  ``fairseq-interactive`` : Generate from raw text with a trained model
-  ``fairseq-validate`` : Validate a model (compute validation loss)
-  ``fairseq-eval-lm`` : Evaluate the perplexity of a trained language
   model
-  ``fairseq-score`` : Compute BLEU

   -  I recommend to use ``sacreBLEU`` instead of ``fairseq-score``.

Tools
-----

Here are some of the most commonly used ones

-  ``scripts/average_checkpoints.py`` : Loads checkpoints and returns a
   model with averaged weights.
-  ``scripts/rm_pt.py`` : Remove unnecessary checkpoints like each epoch
   checkpoints.

Examples: ``examples/``
-----------------------

-  Translation

   -  back translation
   -  noisy channel

      -  alignment

   -  constrained decoding
   -  simultaneous translation
   -  MoE
   -  WMT19 winner system
   -  multilingual translation
   -  scaling NMT

-  Paraphraser
-  Language model
-  Summarization

   -  BART
   -  Pointer generator

-  Unsupervised quality estimation
-  LASER, XLM, Linformer
-  Speech-to-Text
-  wav2vec
-  Story generation

etc.

Components: ``fairseq/*``
-------------------------

-  ``criterions/`` : Compute the loss for the given sample.
-  ``data/`` : Dictionary, dataset, word/sub-word tokenizer
-  ``dataclass/`` : Common options
-  ``distributed/`` : Library for distributed and/or multi-GPU training
-  ``logging/`` : Logging, progress bar, Tensorboard, WandB
-  ``modules/`` : NN layer, sub-network, activation function,
   quantization
-  ``models/``: NN model

   -  BERT, RoBERTa, BART, XLM-R, huggingface model
   -  Non-autoregressive Transformer

      -  NAT
      -  Insertion Transformer
      -  CMLM
      -  Levenshtein Transformer
      -  CRF NAT

   -  Speech-to-Text Transformer
   -  wav2vec
   -  LSTM + Attention (Luong et al., 2015)
   -  Fully convolutional model (Gehring et al., 2017)
   -  Transformer (Vaswani et al., 2017)

      -  Alignment (Garg et al., 2019)
      -  Multilingual

-  ``optim/`` : Optimizers, FP16

   -  Adadelta
   -  Adafactor
   -  Adagrad
   -  Adam
   -  SGD

   etc.

-  ``optim/lr_scheduler/`` : Learning rate scheduler

   -  Cosine
   -  Fixed
   -  Inverse square root (Vaswani et al., 2017)
   -  Polynomial decay
   -  Triangular

   etc.

-  ``tasks/``

   -  Audio pretraining / fine-tuning
   -  Denoising
   -  Language modeling
   -  Masked LM, cross lingual LM
   -  Reranking
   -  Translation

   etc.

-  ``registry.py`` : criterion, model, task, optimizer manager
-  ``search.py``

   -  Beam search
   -  Lexically constrained beam search
   -  Length constrained beam search
   -  Sampling

-  ``sequence_generator.py`` : Generate sequences of a given sentence.
-  ``sequence_scorer.py`` : Score the sequence for a given sentence.
-  ``trainer.py`` : Library for training a network

Training flow of translation 
----------------------------
main: ``fairseq_cli/train.py``

- ``fairseq_cli/hydra_train.py`` sets options and after calls ``fairseq_cli/train.py``.

1. Parse options defined by
   `dataclass <https://docs.python.org/3/library/dataclasses.html>`__

   1. ``fairseq.tasks.translation.TranslationConfig``
   2. ``fairseq.models.transformer.transformer_config.TransformerConfig``
   3. ``fairseq.criterions.label_smoothed_cross_entropy.LabelSmoothedCrossEntropyConfig``
   4. ``fairseq.optim.adam.FairseqAdamConfig``
   5. ``fairseq.dataclass.configs.FairseqConfig``

   Options are stored to `OmegaConf <https://github.com/omry/omegaconf>`_, so it can be
   accessed via attribute style (``cfg.foobar``) and dictionary style
   (``cfg["foobar"]``).

   .. note:: In v0.x, options are defined by ``ArgumentParser``.

2. Setup task

   1. ``fairseq.tasks.translation.Translation.setup_task()`` : class
      method

      1. Load dictionary
      2. Build and return ``self`` (``TranslationTask``).

3. Build model and criterion

   1. ``fairseq.tasks.translation.Translation.build_model()``
      → ``fairseq.models.transformer.transformer_legacy.TransformerModel.build_model()`` : class method

        This method is used to maintain compatibility for v0.x.

      → ``fairseq.models.transformer.transformer_base.TransformerModelBase.build_model()`` : class method

        Build embedding, encoder, and decoder

   2. ``fairseq.criterions.label_smoothed_cross_entropy.LabelSmoothedCrossEntropy``

4. Build trainer

   1. ``fairseq.trainer.Trainer``

      -  Load training set and make data iterator
      -  Build optimizer and learning rate scheduler

5. Start training loop

   1. Call ``fairseq.trainer.Trainer.train_step()``

      1. Reset gradients
      2. Set the model to train mode
      3. Call ``task.train_step()``

         -  Compute the loss of given sentences by
            ``criterion(model, sample)``.
         -  Compute the gradients

      4. Loop i. — iii. until ``cfg.optimizer.update_freq`` to
         accumulate the gradients
      5. Reduce gradients across workers (for multi-node/multi-GPU)
      6. Clip gradients
      7. Update model parameters by ``task.optimizer_step()``
      8. Log statistics

   2. Loop a. until the end of each epoch
   3. Compute validate loss
   4. Save the model checkpoint.

Generation flow of translation
------------------------------
main: ``fairseq_cli/generate.py``

1. Parse options defined by
   `dataclass <https://docs.python.org/3/library/dataclasses.html>`__

   1. ``fairseq.tasks.translation.TranslationConfig``
   2. ``fairseq.models.transformer.transformer_config.TransformerConfig``
   3. ``fairseq.dataclass.configs.FairseqConfig``

2. Setup task

   1. ``fairseq.tasks.translation.Translation.setup_task()`` : class method

      1. Load dictionary
      2. Build and return ``self`` (``TranslationTask``).

3. Load the model and dataset

   1. ``checkpoint_utils.load_model_ensemble()``

      Build the model and load parameters.

   2. ``task.load_dataset()``

      Load the dataset.

4. Build generator

   1. ``task.build_generator() -> fairseq.sequence_generator.SequenceGenerator``

5. Generation

   1. Call ``task.inference_step()``
   2. Call ``SequenceGenerator.generate()``

      - Search with ``fairseq.search.BeamSearch``

   3. Output the results

4. Customize and extend fairseq
===============================

- https://github.com/de9uch1/dbsa
