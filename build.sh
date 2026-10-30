#!/bin/bash
set -e
export STORAGE_DRIVER=vfs
export BUILDAH_ISOLATION=chroot
export DEBIAN_FRONTEND=noninteractive
apt-get update && \
apt-get install -y --no-install-recommends buildah netavark

cd /tmp/nginx
CONT_LATEST="${IMAGE_NAME}:latest"
nice buildah --storage-driver="$STORAGE_DRIVER" \
        bud --isolation="$BUILDAH_ISOLATION" \
        --build-arg-file=argfile.conf \
        -t "$CONT_LATEST" .

buildah --storage-driver "$STORAGE_DRIVER" from --pull=never --name version-finder "$CONT_LATEST"
REV=$(date +"%Y%m%d")
NG_VER=$(buildah --storage-driver "$STORAGE_DRIVER" run version-finder sh -c "nginx -V 2>&1 | grep -oP '(?<=nginx version: nginx/)(.+)$'")
CONT_VER="${NG_VER}_${REV}"
CONT_VER=${CONT_VER//[+~]/_}
# 1.30.4_20260720
echo "Container version: ${CONT_VER}"
CONT_WITH_VER=${CONT_LATEST%%:*}:${CONT_VER}
echo "Container version with date: ${CONT_WITH_VER}"

echo $(cat /run/secrets/GHCR_PACKAGE_RW) | buildah login --password-stdin -u "${ACTOR}" ghcr.io

# 1.30.4_202607204
# 1.30.4
# 1.30
for tag in "${CONT_VER}" "${NG_VER}" "${NG_VER%.*}"; do
  buildah --storage-driver "$STORAGE_DRIVER" tag "${CONT_LATEST}" "${CONT_LATEST%%:*}:${tag}"
  echo Pushing "${tag}"
  buildah --storage-driver "$STORAGE_DRIVER" push "${CONT_LATEST%%:*}:${tag}"
done
# latest
echo Pushing latest
buildah --storage-driver "$STORAGE_DRIVER" push "${CONT_LATEST}"
