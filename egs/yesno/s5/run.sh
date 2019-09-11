#!/bin/bash

train_cmd="utils/run.pl"
decode_cmd="utils/run.pl"
#音频文件下载
if [ ! -d waves_yesno ]; then
  wget http://www.openslr.org/resources/1/waves_yesno.tar.gz || exit 1;
  # was:
  # wget http://sourceforge.net/projects/kaldi/files/waves_yesno.tar.gz || exit 1;
  tar -xvzf waves_yesno.tar.gz || exit 1;
fi

train_yesno=train_yesno
test_base_name=test_yesno

rm -rf data exp mfcc

# Data preparation

local/prepare_data.sh waves_yesno  #wav文件预处理
local/prepare_dict.sh              #字典准备
utils/prepare_lang.sh --position-dependent-phones false data/local/dict "<SIL>" data/local/lang data/lang  #将之前的词典转换为L.fst 以及 topo文件
local/prepare_lm.sh          #将已经生成好的语言模型（s5/input/task.arpabo）转化为Kaldi格式的G.fst

# Feature extraction          
for x in train_yesno test_yesno; do                        #其中ark文件为MFCC的特征向量；scp文件是音频文件或说话人与相应ark文件的对应关系；前缀cmvn为说话人，raw为音频文件。
 steps/make_mfcc.sh --nj 1 data/$x exp/make_mfcc/$x mfcc   #根据wav.scp提取特征,＃1是并行作业数
 steps/compute_cmvn_stats.sh data/$x exp/make_mfcc/$x mfcc #根据feats.scp计算cmn,是为了计算提取特征的CMVN，即为倒谱方差均值归一化
 utils/fix_data_dir.sh data/$x                              #该脚本会修复排序错误
done

# Mono training
steps/train_mono.sh --nj 1 --cmd "$train_cmd" \       #单音素训练,该步骤将生成声学模型。
  --totgauss 400 \
  data/train_yesno data/lang exp/mono0a            
  
# Graph compilation  
utils/mkgraph.sh data/lang_test_tg exp/mono0a exp/mono0a/graph_tgpr  #该步骤生成最终的HCLG.fst.

# Decoding
steps/decode.sh --nj 1 --cmd "$decode_cmd" \
    exp/mono0a/graph_tgpr data/test_yesno exp/mono0a/decode_test_yesno

for x in exp/*/decode*; do [ -d $x ] && grep WER $x/wer_* | utils/best_wer.sh; done
