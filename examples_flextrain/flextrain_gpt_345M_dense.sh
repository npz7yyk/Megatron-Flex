#!/bin/bash
DIR=`pwd`
###############################################################################
### Main configs
## GPT-3 models use 2K sequence length/context window
SEQ_LEN=2048

### The "GPT-3 XXX" below are configs from GPT-3 paper
### https://arxiv.org/abs/2005.14165, choose based on
### your desired model size or build your own configs

## GPT-3 Small 125M
# MODEL_SIZE=0.125
# NUM_LAYERS=12
# HIDDEN_SIZE=768
# NUM_ATTN_HEADS=12
# GLOBAL_BATCH_SIZE=256
# LR=6.0e-4
# MIN_LR=6.0e-5

# GPT-3 Medium 350M
MODEL_SIZE=0.35
NUM_LAYERS=24
HIDDEN_SIZE=1024
NUM_ATTN_HEADS=16
GLOBAL_BATCH_SIZE=128
LR=3.0e-4
MIN_LR=3.0e-5

## GPT-3 Large 760M
# MODEL_SIZE=0.76
# NUM_LAYERS=24
# HIDDEN_SIZE=1536
# NUM_ATTN_HEADS=16
# GLOBAL_BATCH_SIZE=256
# LR=2.5e-4
# MIN_LR=2.5e-5

## GPT-3 XL 1.3B
# MODEL_SIZE=1.3
# NUM_LAYERS=24
# HIDDEN_SIZE=2048
# NUM_ATTN_HEADS=16
# GLOBAL_BATCH_SIZE=512
# LR=2.0e-4
# MIN_LR=2.0e-5

## GPT-3 2.7B
# MODEL_SIZE=2.7
# NUM_LAYERS=32
# HIDDEN_SIZE=2560
# NUM_ATTN_HEADS=32
# GLOBAL_BATCH_SIZE=512
# LR=1.6e-4
# MIN_LR=1.6e-5

## GPT-3 6.7B
# MODEL_SIZE=6.7
# NUM_LAYERS=32
# HIDDEN_SIZE=4096
# NUM_ATTN_HEADS=32
# GLOBAL_BATCH_SIZE=1024
# LR=1.2e-4
# MIN_LR=1.2e-5

## GPT-3 13B
# MODEL_SIZE=13
# NUM_LAYERS=40
# HIDDEN_SIZE=5120
# NUM_ATTN_HEADS=40
# GLOBAL_BATCH_SIZE=1024
# LR=1.0e-4
# MIN_LR=1.0e-5

## GPT-3 33B
# MODEL_SIZE=33
# NUM_LAYERS=60
# HIDDEN_SIZE=6656
# NUM_ATTN_HEADS=52
# GLOBAL_BATCH_SIZE=1024
# LR=0.6e-4
# MIN_LR=0.6e-5

## GPT-3 175B
# MODEL_SIZE=175
# NUM_LAYERS=96
# HIDDEN_SIZE=12288
# NUM_ATTN_HEADS=96
# GLOBAL_BATCH_SIZE=1536
# LR=0.6e-4
# MIN_LR=0.6e-5
###############################################################################
### Training duration configs
## The main termination condition, original GPT-3 paper trains for 300B tokens
## For MoE model, we found sometimes training a bit more to 330B tokens helps
TRAIN_TOKENS=300000000000
# TRAIN_TOKENS=330000000000

## TRAIN_SAMPLES is another termination condition and also affect the number of 
## data samples to be indexed. Since we want to reach the TRAIN_TOKENS
## above, and techniques like curriculum learning has less token in some steps,
## so we just set this config large enough to make sure we have enough
## processed data and don't terminate by TRAIN_SAMPLES.
TRAIN_SAMPLES=$(( ${TRAIN_TOKENS} * 3 / ${SEQ_LEN} ))

## Another termination condition in minutes. Set it large enough to avoid
## undesired early termination.
EXIT_DURATION=30000000
###############################################################################
### LR configs
## LR warmup and decay duration, this token-based config is preferable since
## no need to readjust when the batch size/seqlen is changed.
## Original GPT-3 paper uses 375M warmup tokens and 260B decay tokens.
## For MoE model, we found that setting the decay token to 300B helps.
WARMUP_TOKENS=375000000
LR_DECAY_TOKENS=260000000000
# LR_DECAY_TOKENS=300000000000
###############################################################################
### Parallelism configs
## Micro batch size per GPU
## Make sure that BATCH_SIZE <= GLOBAL_BATCH_SIZE*PP_SIZE*MP_SIZE/NUM_GPUS
BATCH_SIZE=4

## Model parallelism, 1 is no MP
MP_SIZE=1

## Pipeline parallelism
## Currently we don't support PP for MoE. To disable PP, set PP_SIZE
## to 1 and use the "--no-pipeline-parallel" arg.
PP_SIZE=1
NUM_GPUS=4
###############################################################################
### Distributed configs
GPUS_PER_NODE=$NUM_GPUS
NNODES=1
NODE_RANK=0
MASTER_ADDR=localhost
MASTER_PORT=30000
###############################################################################
### MoE configs
## Number of experts. EP_SIZE 1 means dense model without MoE
EP_SIZE=1
# EP_SIZE=128

if [[ $EP_SIZE -gt $NUM_GPUS ]]; then
    EP_PARALLEL_SIZE=$NUM_GPUS
else
    EP_PARALLEL_SIZE=$EP_SIZE
fi

## Original GPT-3 model always set min LR at 10% of max LR. For MoE model, we
## found that lower LR and min LR (than the base dense model) helps.
## For 1.3B MoE-128 model we used LR=1.2e-4 and MIN_LR=1.0e-6.
## For 350M MoE-128 model we used LR=2.0e-4 and MIN_LR=2.0e-6, but they are not
## heavily tuned.
# LR=2.0e-4
# MIN_LR=2e-06

## Coefficient for MoE loss. We find that 0.01 is a good value at least for
## 1.3B MoE-128 model
MLC=0.01

## Below configs adjust the MoE expert token capacity limit during training and
## eval. To completely disable capacity limit, set MOE_DROP_TOKEN to false.
## Larger capacity factor or disabling capacity limit could improve training
## convergence, but will also reduce training throughput.
MOE_TRAIN_CAP_FACTOR=1.0
MOE_EVAL_CAP_FACTOR=1.0
MOE_MIN_CAP=4
MOE_DROP_TOKEN="true"
# MOE_DROP_TOKEN="false"
###############################################################################
### Curriculum learning (CL) configs
## Enable/disable CL
CL_ENABLED="false"
## Consult the tutorial https://www.deepspeed.ai/tutorials/curriculum-learning/
## for tuning the following configs
CL_START_SEQLEN=80
CL_AVG_SEQLEN=$(( (${CL_START_SEQLEN} + ${SEQ_LEN}) / 2 ))
CL_TOKENS=60
CL_TOKENS=$((${CL_TOKENS} * 1000000000))
CL_STEP=$(( ${CL_TOKENS} / (${GLOBAL_BATCH_SIZE} * ${CL_AVG_SEQLEN}) ))
###############################################################################
### Misc configs
LOG_INTERVAL=10
EVAL_ITERS=10
EVAL_INTERVAL=100
SAVE_INTERVAL=1000

## Standard deviation for weight initialization
## We used 0.014 for 350M/1.3B dense/MoE models, and used 0.01 for 6.7B
## dense model. Usually larger model needs lower std.
INIT_STD=0.014
# INIT_STD=0.01

## Activation checkpointing saves GPU memory, but reduces training speed
ACTIVATION_CHECKPOINT="true"
# ACTIVATION_CHECKPOINT="false"
###############################################################################
### Data configs
VOCAB_PATH=/shared_ssd_storage/yikang/gpt-data/gpt2-vocab.json
MERGE_PATH=/shared_ssd_storage/yikang/gpt-data/gpt2-merges.txt
DATA_BLEND=/shared_ssd_storage/yikang/gpt-data/meg-gpt2-oscar-en-10k_text_document
###############################################################################

distributed_args="
    --nproc_per_node ${GPUS_PER_NODE} \
    --nnodes ${NNODES} \
    --node_rank ${NODE_RANK} \
    --master_addr ${MASTER_ADDR} \
    --master_port ${MASTER_PORT}
"

data_options=" \
    --vocab-file ${VOCAB_PATH} \
    --merge-file ${MERGE_PATH} \
    --data-path ${DATA_BLEND} \
    --data-impl mmap
"

megatron_options=" \
    --override-opt_param-scheduler \
    --adam-beta1 0.9 \
    --adam-beta2 0.95 \
    --tensor-model-parallel-size ${MP_SIZE} \
    --moe-expert-parallel-size ${EP_PARALLEL_SIZE} \
    --num-experts ${EP_SIZE} \
    --moe-loss-coeff ${MLC} \
    --moe-train-capacity-factor ${MOE_TRAIN_CAP_FACTOR} \
    --moe-eval-capacity-factor ${MOE_EVAL_CAP_FACTOR} \
    --moe-min-capacity ${MOE_MIN_CAP} \
    --init-method-std ${INIT_STD} \
    --lr-decay-tokens ${LR_DECAY_TOKENS} \
    --lr-warmup-tokens ${WARMUP_TOKENS} \
    --micro-batch-size ${BATCH_SIZE} \
    --exit-duration-in-mins ${EXIT_DURATION} \
    --global-batch-size ${GLOBAL_BATCH_SIZE} \
    --num-layers ${NUM_LAYERS} \
    --hidden-size ${HIDDEN_SIZE} \
    --num-attention-heads ${NUM_ATTN_HEADS} \
    --seq-length ${SEQ_LEN} \
    --max-position-embeddings ${SEQ_LEN} \
    --train-tokens ${TRAIN_TOKENS} \
    --train-samples ${TRAIN_SAMPLES} \
    --lr ${LR} \
    --min-lr ${MIN_LR} \
    --lr-decay-style cosine \
    --split 98,2,0 \
    --log-interval ${LOG_INTERVAL} \
    --eval-interval ${EVAL_INTERVAL} \
    --eval-iters ${EVAL_ITERS} \
    --save-interval ${SAVE_INTERVAL} \
    --weight-decay 0.1 \
    --clip-grad 0.0 \
    --hysteresis 2 \
    --num-workers 0 \
    --fp16
"

flextrain_options=" \
    --flextrain \
    --flextrain-config config_gpt_345M_dense.json
"

if [ "${ACTIVATION_CHECKPOINT}" = "true" ]; then
megatron_options="${megatron_options} \
    --checkpoint-activations"
fi

if [[ $EP_SIZE -gt 1 ]]; then
megatron_options="${megatron_options} \
    --create-moe-param-group"
fi

if [ "${MOE_DROP_TOKEN}" = "false" ]; then
megatron_options="${megatron_options} \
    --disable-moe-token-dropping"
fi

torchrun ${distributed_args} ../pretrain_gpt.py \
    ${flextrain_options} \
    ${megatron_options} \
    ${data_options}