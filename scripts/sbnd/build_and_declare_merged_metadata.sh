#!/usr/bin/sh

FILENAME=$1
MERGED_FILE=${FILENAME}
FULL_FILE=${FILENAME}
FILEDIR=$(dirname ${MERGED_FILE})
if [[ "${FILEDIR}" != /* ]]; then
    echo "Must provide an absolute path to a file"
    exit 1
fi
FILENAME=$(basename ${FILENAME})
MERGED_FILE=$(basename ${MERGED_FILE})
FILEJSON=${FILENAME/root/json}
FILENAME=${FILENAME/merged_/}

samweb -e sbnd get-metadata --json ${FILENAME} > ${FILEJSON}

# Start editing the metadata fields - need to change name, size, date, checksum at a minimum
# Also remove file id, samweb will deal with it
sed -i "s/\"file_name\": \"${FILENAME}\",/\"file_name\": \"${MERGED_FILE}\",/g" ${FILEJSON}
sed -i '/\"file_id\"/d' ${FILEJSON}
file_size=$(stat -c %s ${FULL_FILE} | awk -F " " '{print $1}')
sed -i "s/\(\"file_size\":[[:space:]]*\).*/\1${file_size}/" ${FILEJSON}
sed -i 's/\(\"create_date\":[[:space:]]*"\)[^"]*/\1'"$(stat -c %y ${FULL_FILE} | date -u -f - +"%Y-%m-%dT%H:%M:%S+00:00")"'/' ${FILEJSON}
enstore_checksum=$(samweb file-checksum --type=enstore ${FULL_FILE} | tr -d "[" | tr -d "]" | awk -F ":" '{print $2}')
adler32_checksum=$(samweb file-checksum --type=adler32 ${FULL_FILE} | tr -d "[" | tr -d "]" | awk -F ":" '{print $2}')
md5_checksum=$(samweb file-checksum --type=md5 ${FULL_FILE} | tr -d "[" | tr -d "]" | awk -F ":" '{print $2}')
sed -i "s/\(\"enstore:\)[^\"].*/\1${enstore_checksum}/g" ${FILEJSON}
sed -i "s/\(\"adler32:\)[^\"].*/\1${adler32_checksum}/g" ${FILEJSON}
sed -i "s/\(\"md5:\)[^\"].*/\1${md5_checksum}/g" ${FILEJSON}

samweb declare-file ${FILEJSON}
samweb add-file-location ${MERGED_FILE} ${FILEDIR}

echo "Done"
