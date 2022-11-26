#!/bin/bash
# ==============================================================================
# Copyright (C) 2018-2022 Intel Corporation
#
# SPDX-License-Identifier: MIT
# ==============================================================================
set -e

INPUT="https://github.com/intel-iot-devkit/sample-videos/raw/master/head-pose-face-detection-female-and-male.mp4" # Supported values: url, /dev/video0, udpsrc, filesrc
DEVICE="CPU"        # Supported values: CPU, GPU
OUTPUT="display"    # Supported values: display, fps, json, display-and-json, "host=192.168.251.1 port=9001"
OUTPUTFORMAT="file" # Supported values: file, console, fifo
FPSCOUNTER="fps"    # Supported values: fps, nofps
INPUTWIDTH=         # Input video width, no to use src resolution
SRCRECORDFILE=      # Video source record file name *.mp4, empty for not recording

__usage="
Usage: $(basename $0) [OPTIONS]

Options:
  -i, --input   </dev/video*|://|port=UDPSRC|FILESRC>            Input type
  -d, --device  <CPU|GPU>                                        Compute device type, not applicable for output=\"port=\"
  -o, --output  <display|fps|json|display-and-json|port=UDPSINK> Output format
  -f, --fileformat <console|file|fifo>                           Output file format
  -p, --sinkfps <fps|nofps>                                      Output FPS counter or not
  -w, --width   <width>                                          Input video width
  -r, --record  <*.mp4>                                          Video source recording file name
"
usage() { echo "$__usage" 1>&2; exit 1; }

while getopts ":i:d:o:f:p:w:r:" o; do
    case "${o}" in
        i|input)
            INPUT=${OPTARG}
            ;;
        d|device)
            DEVICE=${OPTARG}
            ;;
        o|output)
            OUTPUT=${OPTARG}
            ;;
        f|fileformat)
            OUTPUTFORMAT=${OPTARG}
            ;;
        p|sinkfps)
            FPSCOUNTER=${OPTARG}
            ;;
        w|width)
            INPUTWIDTH=${OPTARG}
            ;;
        r|record)
            SRCRECORDFILE=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "${INPUTWIDTH}" ]; then
  SOURCE_CONVERT=""
else
  SOURCE_CONVERT="! decodebin ! videoconvert ! videoscale ! video/x-raw,width=${INPUTWIDTH},framerate=30/1"
fi

if [[ $OUTPUT == *"port="* ]]; then
  echo "run as client: $(basename $0) -i ${INPUT} -w ${INPUTWIDTH} -r ${SRCRECORDFILE} -o ${OUTPUT}"
elif [[ $INPUT == *"port="* ]]; then
  echo "run as server: $(basename $0) -i ${INPUT} -d ${DEVICE} -o ${OUTPUT} -f ${OUTPUTFORMAT} -p ${FPSCOUNTER}"
else
  echo "run on single host: $(basename $0) -i ${INPUT} -w ${INPUTWIDTH} -r ${SRCRECORDFILE} -d ${DEVICE} -o ${OUTPUT} -f ${OUTPUTFORMAT} -p ${FPSCOUNTER}"
fi

METAFILENAME=/tmp/output.json

MODEL1=face-detection-adas-0001
MODEL2=age-gender-recognition-retail-0013
MODEL3=emotions-recognition-retail-0003
MODEL4=landmarks-regression-retail-0009

if [[ $INPUT == "/dev/video"* ]]; then
  JPEG="$(v4l2-ctl -d ${INPUT} --list-formats-ext)"
  if [[ ${JPEG} == *"jpeg"* ]]; then
    SOURCE_ELEMENT="v4l2src device=${INPUT} ! jpegdec ${SOURCE_CONVERT}"
  else
    SOURCE_ELEMENT="v4l2src device=${INPUT} ${SOURCE_CONVERT}"
  fi
elif [[ $INPUT == *"://"* ]]; then
  SOURCE_ELEMENT="urisourcebin buffer-size=4096 uri=${INPUT} ${SOURCE_CONVERT}"
elif [[ $INPUT == *"port="* ]]; then
  SOURCE_ELEMENT="udpsrc ${INPUT} caps=\"application/x-rtp, media=(string)video, clock-rate=(int)90000, encoding-name=(string)H264\" ! rtph264depay"
else
  SOURCE_ELEMENT="filesrc location=${INPUT} ${SOURCE_CONVERT}"
fi

if [[ $SRCRECORDFILE == *"mp4"* ]]; then
  SOURCE_ELEMENT="${SOURCE_ELEMENT} ! tee name=t t. ! queue ! x264enc ! mp4mux ! filesink location=${SRCRECORDFILE} -e t. ! queue leaky=1 ! autovideosink sync=false t. ! queue"
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
  SINK_ELEMENT="x264enc speed-preset=superfast tune=zerolatency ! rtph264pay ! udpsink $OUTPUT"
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
  PIPELINE="gst-launch-1.0 $SOURCE_ELEMENT ! decodebin ! videoconvert !\
  $SINK_ELEMENT"
else
  PIPELINE="gst-launch-1.0 $SOURCE_ELEMENT ! decodebin ! videoconvert ! queue !\
  gvadetect model=$DETECT_MODEL_PATH device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH model-proc=$MODEL2_PROC device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH1 model-proc=$MODEL3_PROC device=$DEVICE ! queue ! \
  gvaclassify model=$CLASS_MODEL_PATH2 model-proc=$MODEL4_PROC device=$DEVICE ! queue ! \
  $SINK_ELEMENT"
fi

echo ${PIPELINE}
$PIPELINE
