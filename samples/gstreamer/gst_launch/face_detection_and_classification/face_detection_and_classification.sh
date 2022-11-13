#!/bin/bash
# ==============================================================================
# Copyright (C) 2018-2022 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================
set -e

INPUT=${1:-https://github.com/intel-iot-devkit/sample-videos/raw/master/head-pose-face-detection-female-and-male.mp4}
DEVICE=${2:-CPU}
OUTPUT=${3:-display} # Supported values: display, fps, json, display-and-json, "host=192.168.251.1 port=9001"
OUTPUTFORMAT=${4:-file} # Supported values: file, console, fifo
FPSCOUNTER=${5:-fps} # Supported values: fps, nofps
METAFILENAME=/tmp/output.json

MODEL1=face-detection-adas-0001
MODEL2=age-gender-recognition-retail-0013
MODEL3=emotions-recognition-retail-0003
MODEL4=landmarks-regression-retail-0009

if [[ $INPUT == "/dev/video"* ]]; then
  SOURCE_ELEMENT="v4l2src device=${INPUT} ! jpegdec ! videoconvert ! videoscale ! video/x-raw,width=1280"
elif [[ $INPUT == *"://"* ]]; then
  SOURCE_ELEMENT="urisourcebin buffer-size=4096 uri=${INPUT}"
elif [[ $INPUT == *"port="* ]]; then
  SOURCE_ELEMENT="udpsrc ${INPUT} caps = \"application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264 \" ! rtpjitterbuffer"
else
  SOURCE_ELEMENT="filesrc location=${INPUT}"
fi

rm -f ${METAFILENAME}
if [[ $OUTPUTFORMAT == "console" ]]; then
  OUTPUT_PROPERTY=""
elif [[ $OUTPUTFORMAT == "file" ]]; then
  OUTPUT_PROPERTY="file-path=${METAFILENAME}"
else
  mkfifo ${METAFILENAME}
  OUTPUT_PROPERTY="file-path=${METAFILENAME}"
fi

if [[ $FPSCOUNTER == 'fps' ]]; then
  FPSCOUNTER="gvafpscounter !"
else
  FPSCOUNTER=""
fi

if [[ $OUTPUT == "display" ]] || [[ -z $OUTPUT ]]; then
  SINK_ELEMENT="gvawatermark ! videoconvert ! $FPSCOUNTER autovideosink sync=false"
elif [[ $OUTPUT == "fps" ]]; then
  SINK_ELEMENT="$FPSCOUNTER fakesink async=false "
elif [[ $OUTPUT == "json" ]]; then
  SINK_ELEMENT="gvametaconvert ! gvametapublish file-format=json-lines $OUTPUT_PROPERTY ! fakesink async=false "
elif [[ $OUTPUT == "display-and-json" ]]; then
  SINK_ELEMENT="gvawatermark ! gvametaconvert ! gvametapublish file-format=json-lines $OUTPUT_PROPERTY ! videoconvert ! $FPSCOUNTER autovideosink sync=false"
elif [[ $OUTPUT == *"port="* ]]; then
  SINK_ELEMENT="x264enc ! rtph264pay ! udpsink $OUTPUT"
else
  echo Error wrong value for OUTPUT parameter
  echo Valid values: "display" - render to screen, "fps" - print FPS, "json" - write to ${METAFILENAME}, "display-and-json" - render to screen and write to ${METAFILENAME}, "host=192.168.251.1 port=9001" - stream video to remote host
  exit
fi

PROC_PATH() {
    echo $(dirname "$0")/model_proc/$1.json
}

DETECT_MODEL_PATH=${MODELS_PATH}/intel/face-detection-adas-0001/FP32/face-detection-adas-0001.xml
CLASS_MODEL_PATH=${MODELS_PATH}/intel/age-gender-recognition-retail-0013/FP32/age-gender-recognition-retail-0013.xml
CLASS_MODEL_PATH1=${MODELS_PATH}/intel/emotions-recognition-retail-0003/FP32/emotions-recognition-retail-0003.xml
CLASS_MODEL_PATH2=${MODELS_PATH}/intel/landmarks-regression-retail-0009/FP32/landmarks-regression-retail-0009.xml

MODEL2_PROC=$(PROC_PATH $MODEL2)
MODEL3_PROC=$(PROC_PATH $MODEL3)
MODEL4_PROC=$(PROC_PATH $MODEL4)

if [[ $OUTPUT == *"port="* ]]; then
  PIPELINE="gst-launch-1.0 $SOURCE_ELEMENT ! decodebin ! \
  $SINK_ELEMENT"
else
  PIPELINE="gst-launch-1.0 $SOURCE_ELEMENT ! decodebin ! \
  gvadetect model=$DETECT_MODEL_PATH device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH model-proc=$MODEL2_PROC device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH1 model-proc=$MODEL3_PROC device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH2 model-proc=$MODEL4_PROC device=$DEVICE ! queue ! \
  $SINK_ELEMENT"
fi

echo ${PIPELINE}
$PIPELINE
