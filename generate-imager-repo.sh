#! /bin/bash -e
# Generate/update the Raspberry Pi Imager "custom repository" JSON (imager-repo.json)
# so that https://<bucket>.s3.amazonaws.com/imager-repo.json always lists the current
# Motus-built Sensorgnome images, with correct checksums/sizes, and so that Imager
# offers its "OS Customisation" screen (hostname/user/password/ssh/locale) for them
# (see doc/schema-notes.md and doc/os-sublist-example.json in raspberrypi/rpi-imager).
#
# This file is hand-curated beyond what this script writes: it also lists TvE's own
# releases (stable / release candidate / development) alongside Motus's. This script
# only ever replaces the ONE entry whose "name" matches the channel it was called
# with (see the jq filter below) -- every other entry, including all of TvE's, is
# downloaded, left untouched, and re-uploaded as-is. So this is safe to run from CI
# without clobbering anything someone else added by hand.
#
# This does NOT make WiFi customisation work: Imager configures WiFi via NetworkManager,
# which this image does not ship (see base-armv7-rpi-bookworm.pifile).
#
# Usage: ./generate-imager-repo.sh <stable|testing> <img-path> <zip-path> <version> [release-date]
#
# Run this once per build, right after the .img/.zip are produced, before/after uploading
# the image itself. It downloads the existing imager-repo.json from S3 (if any), replaces
# only the entry for the given channel, and re-uploads the merged file, so a testing build
# never clobbers the stable entry and vice versa.

CHANNEL=$1
IMG=$2
ZIP=$3
VERSION=$4
DATE=${5:-$(date -u +"%Y-%m-%d %H:%M:%S UTC")}

if [[ -z $CHANNEL || -z $IMG || -z $ZIP || -z $VERSION ]]; then
    echo "Usage: $0 <stable|testing> <img-path> <zip-path> <version> [release-date]"
    exit 1
fi
if [[ $CHANNEL != stable && $CHANNEL != testing ]]; then
    echo "channel must be 'stable' or 'testing', got: $CHANNEL"
    exit 1
fi

BUCKET=sensorgnome-982081078525-us-east-1-an
REPO_KEY=imager-repo.json
BASE_URL=https://$BUCKET.s3.amazonaws.com

# Served through the motusaws artifacts API rather than a raw S3 URL. The "key" query
# param is the S3 key of the real, versioned zip the build just uploaded (same filename
# as $SG_ZIP in build.yml) -- there is no mutable "latest" alias, so this script updates
# the URL itself on every run, not just the checksums. Key layout mirrors TvE's own
# bucket convention: releases directly under images/, testing/development builds under
# images/pimod/ -- build.yml must upload the zip to the matching S3 key for this to
# resolve (see the "Upload ... to AWS S3 repo" steps there).
ARTIFACTS_API=https://motusaws.duckdns.org/artifacts/api/download
ZIP_NAME=$(basename "$ZIP")

if [[ $CHANNEL == stable ]]; then
    NAME="Motus Sensorgnome (stable)"
    DESCRIPTION="Sensorgnome $VERSION - stable release. https://docs.motus.org/sensorgnome-v2/"
    IMG_URL="$ARTIFACTS_API?key=images%2F$ZIP_NAME"
else
    NAME="Motus Sensorgnome (development)"
    DESCRIPTION="Sensorgnome $VERSION - latest testing build, may be unstable. https://docs.motus.org/sensorgnome-v2/"
    IMG_URL="$ARTIFACTS_API?key=images%2Fpimod%2F$ZIP_NAME"
fi

echo "Hashing $IMG and $ZIP..."
EXTRACT_SIZE=$(stat -c%s "$IMG")
EXTRACT_SHA256=$(sha256sum "$IMG" | cut -d" " -f1)
DOWNLOAD_SIZE=$(stat -c%s "$ZIP")
DOWNLOAD_SHA256=$(sha256sum "$ZIP" | cut -d" " -f1)

# Start from whatever is already published so the other channel's entry is preserved.
aws s3 cp --no-progress "s3://$BUCKET/$REPO_KEY" existing-imager-repo.json \
    || echo '{"os_list":[]}' >existing-imager-repo.json

jq --arg name "$NAME" \
   --arg desc "$DESCRIPTION" \
   --arg url "$IMG_URL" \
   --arg icon "$BASE_URL/imager-icon.png" \
   --arg website "https://docs.motus.org/sensorgnome-v2/" \
   --arg date "$DATE" \
   --argjson esize "$EXTRACT_SIZE" \
   --arg esha "$EXTRACT_SHA256" \
   --argjson dsize "$DOWNLOAD_SIZE" \
   --arg dsha "$DOWNLOAD_SHA256" \
   '.os_list = ([.os_list[]? | select(.name != $name)] + [{
        name: $name,
        description: $desc,
        icon: $icon,
        url: $url,
        website: $website,
        release_date: $date,
        extract_size: $esize,
        extract_sha256: $esha,
        image_download_size: $dsize,
        image_download_sha256: $dsha,
        devices: ["pi2-32bit", "pi3-32bit", "pi4-32bit", "cm3-32bit", "cm4-32bit"],
        architecture: "armhf",
        init_format: "systemd"
    }])' existing-imager-repo.json >imager-repo.json

echo "Publishing s3://$BUCKET/$REPO_KEY ($CHANNEL -> $VERSION, $DATE)"
aws s3 cp --no-progress imager-repo.json "s3://$BUCKET/$REPO_KEY"
echo "Imager repository URL: $BASE_URL/$REPO_KEY"
