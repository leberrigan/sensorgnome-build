#! /bin/bash -e

#deb-s3 help copy

# Bullseye used testing and stable
# Figure out versions of sensorgnome dependencies
# wget -q -O Packages-testing \
#     https://sensorgnome.s3.us-east-2.amazonaws.com/dists/testing/main/binary-armhf/Packages
# wget -q -O Packages-stable \
#     https://sensorgnome.s3.us-east-2.amazonaws.com/dists/stable/main/binary-armhf/Packages
# Bookworm uses booktest and bookworm
wget -q -O Packages-booktest \
    https://sensorgnome-982081078525-us-east-1-an.s3.us-east-1.amazonaws.com/dists/booktest/main/binary-armhf/Packages
wget -q -O Packages-bookworm \
    https://sensorgnome-982081078525-us-east-1-an.s3.us-east-1.amazonaws.com/dists/bookworm/main/binary-armhf/Packages

#deps=$(awk -v ORS= '/^Depends:/,/[^,]$/' DEBIAN/control | sed -e 's/^\S*://' -e 's/ *, */ /g')
deps=$(egrep '^Package' Packages-booktest | sed -e 's/^\S*:\s*//' | sort -u)

for d in $deps; do
    version_t=$(awk '/^Package:/{pkg=$2} /^Version/&&pkg=="'$d'"{print $2}' Packages-booktest | sort | tail -1)
    version_s=$(awk '/^Package:/{pkg=$2} /^Version/&&pkg=="'$d'"{print $2}' Packages-bookworm | sort | tail -1)
    echo "$d -- testing: $version_t, stable: $version_s"
    if [[ x$version_t != $version_s ]]; then
        out=$(deb-s3 copy \
        --bucket=sensorgnome-982081078525-us-east-1-an \
        --s3-region="$S3_REGION" \
        --preserve-versions \
        --sign=1DC0C66E4594570A \
        --arch=armhf \
        --codename=booktest \
        --component=main \
        "$d" bookworm main \
        --versions="$version_t"
        )
        if [[ "$out" =~ "ERROR" ]]; then exit 1; fi
    fi
done
echo ""
