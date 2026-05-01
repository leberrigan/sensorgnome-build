# Build Sensorgnome Images and Packages

This repository contains scripts to build a complete Sensorgnome flash image,
currently only for Raspberry Pi.

This README is about building the Sensorgnome software.
__Please refer to the [documentation](https://docs.motus.org/sensorgnome-v2/)
for information on installing and using a Sensorgnome.__

The whole build process from scratch consists of 3 steps:

- build a dockcross docker image to be able to cross-compile for the target architecture & OS
- use the dockcross image to build all the sensorgnome packages
- use the packages to build a bootable sensorgnome flash image

This repository only deals with the third step. The first step is found in the
sensorgnome-dockcross repo, which results in a docker image on DockerHub
(currently `tvoneicken/sensorgnome-dockcross:armv7-rpi-bookworm-main`).
Unless this image needs to be rebuilt the easiest is to use the DockerHub one.

The second step should be handled within all the respective repositories and ideally each
repo should have a github worflow that automatically produces the packages on push.
Until all repos are converted to this new scheme, some have been built manually and
uploaded to S3.
The outcome of all this is a bunch of packages in some downloadable location, currently
`https://https://motus-builds.s3.us-east-2.amazonaws.com/<owner>/<repo>/<branch>/*.deb`.
See this [crude file listing](https://motus-builds.s3.us-east-2.amazonaws.com/index.html).
The deb packages are also uploaded to the apt repo
https://sensorgnome.s3.amazonaws.com

The final step is handled in this repo using pimod. Pimod uses a docker container and QEMU
(a processor emulator) to customize an existing rPi or other ARM image.
This is used to load up an official Raspberry Pi OS image, install all the packages
produced in the previous step, apply some final tweaks, and save the result as a
bootable Sensorgnome image.
The output consists of the starting image, an intermediate "base" image, and the final
"sg" image in S3 as
`https://https://motus-builds.s3.us-east-2.amazonaws.com/<owner>/sensorgnome-build/<branch>/sg-*.img`.

Note: the previous version of all this used pi-gen to produce the image and there are a
few other tools available to do the same. Overall the focus should be on installing the
debian packages and they should each do everything necessary for their operation without
requiring additional build steps here. The result ought to be that the specific tool used
for the final image assembly is unimportant as long as a functional clean image pops out.

The switch from pi-gen was motivated by
[these comments](https://github.com/RPi-Distro/pi-gen/issues/486)
where the maintainer states "pi-gen serves its primary purpose of building the official
release images well enough", i.e., it's not designed for customizing.
Pimod's focus is customization.

---


## Lucas notes

- Repos that are related to SGs all have a workflow `build.yml` that's triggered on 'push' which runs `generate-deb.yml` where it builds a ".deb" package and stores it in an AWS bucket.
- That means, every time a repo is pushed, a ".deb" package gets automatically generated, but not a new software image.
- In order to build a new software image, the github automation "promote-packages" needs to be run. 
- AWS bucket is accessed using aws_roles with OIDC.
- Every repo has a build file called `gen-packages.sh` which gets run by `generate-deb.yml` if nothing is specified under `inputs.command`.
- It feels like I had to make a lot of changes to the build files to get it to work. I'm not sure if this is because the process is somewhat fragile due to dependencies and standards constantly changing, or if it's because of my incompetence. However, it appears to be mostly related to switching over to a different AWS bucket that doesn't have ACL supported, which is reassuring.

## Changes made by Lucas

### General
	- Changed AWS paths from tve to Motus AWS
	- I had to remove acl public reads since I don't have it enabled in my bucket and I don't think it's recommended any longer.

### `build.yml`
	- Dropped debian backports when installing dhcp since it's no longer well supported.
	- Dropped `sudo apt-get upgrade -y` since it's causing more harm than good.
	- Switched libqmi version from `1.37.1` to `main` since ModemManager now requires a minimum version > `1.37.95`. May be unstable?

### `generate-deb.yml`
	- Update deb-s3 to accommodate acl-free buckets




Part 1: (Re-)Build Docker Hub Image
------
Probably unecessary. Just use what's already available in dockerhub.
#### Steps
1. Make sure Docker is running.
1. Open the terminal and enter `wsl` to enter the Windows Subsystem for Linux
	- Tip: do this from the embedded within Visual Studio Code with your repo loaded to make things faster.
1. Navigate to parent folder where the repo exists. `cd ..`
1. Start the container instance
	```
	bash dockcross-armv7-rpi-bookworm \
	--image tvoneicken/sensorgnome-dockcross:armv7-rpi-bookworm-main \
	bash
	```
1. From inside the container, run:
	```
	sudo apt-get update
	sudo apt-get install -y fakeroot debhelper-compat
	dpkg-buildpackage -b
	```

---



Part 2: Create *.deb Packages
-----
Automated
#### Steps
1. Create a GPG key:
	a. `gpg --full-generate-key`
  	b. `gpg --export --armor <KEYID> > sensorgnome.gpg`
	c. Upload it to the AWS bucket.
1. Every repo  that will be part of the final build needs to have GPG_PASSPHRASE and GPG_PRIVATE_KEY set in the repo secrets (or organisation secrets).
1. Every repo also needs to have a GitHub Workflow `build.yml` file in it.
1. Whenever a commit gets pushed to a repo, the workflow triggers and builds a .deb package and places it in an AWS folder ([BUCKET]/pool/[booktest|bookworm])


---


Part 3: Build a new SG image
-----
#### Steps
1. Whenever a 




Continue TvE notes
----

## Operation

The image build process is organized as follows:

- a `manifest-xxx' file specifies what is to be built, such as the official OS base image,
  the packagaes to install, the dockcross image to use, the name of the final image, etc.
- a `base-xxx.pifile` tells pimod how to construct a "base image" from the official OS image;
  the intent being that only standard packages get installed that are unlikely to change.
- a `sg-xxx.pifile` tells pimod how to construct the final sensorgnome image from the base
  image by adding all the sensorgnome stuff that may often change.
- the `build.sh` script downloads the original OS image, the sensorgnome packages, and
  then runs pimod two times to generate first the base image and then the final image.
- the split into a base image and a final image is motivated by the fact that building the
  base image takes a long time due to the many packages that get downloaded and updated
  and it's nice to be able to iterate more quickly on the sensorgnome stuff that changes.
- the `build.sh` tries to avoid re-downloading or re-building things that are already there,
  to start from a clean slate remove the `images` and `packages` directories.

## Debian repository

- Sensorgnome packages get uploaded to a debian repository at https://sensorgnome.s3.amazonaws.com/
- Each repository (sensorgnome-support, sensorgnome-control, fcd, ...) uses the `generate-deb.yml`
  workflow found in this repository to add its packages to the _booktest_ codename.
- In this repository, the `generate-package.sh` script generates a `sensorgnome` package that
  depends on the latest version of the packages in _testing_.
- The version dependency of the `sensorgnome` package is ">=", which means that as soon as
  a new package is in the repo it can be upgraded via apt. The `sensorgnome` package itself does
  not need to be upgraded.
- The `sensorgnome` package is published to the _bookworm_ codename and images are produced to
  use the _bookworm_ branch. This means that _bookworm_ gets the version found in _testing_ at the
  time the `sensorgnome` package is built&uploaded. This also means that all plain sensorgnome
  installs only upgrade to versions found in _bookworm_, i.e., versions from which newer images
  have been built.
- To use the packages in booktest, one has to switch `/etc/apt/sources.list.d/sensorgnome.list`
  from _bookworm_ to _booktest_.

## Docker

The reason the build process uses docker is that it allows carefully constructed OS images with
all the right tools to be run on almost any platform. Together with QEMU it, in addition,
allows the final image construction to be run on an emulated ARM platform. This way running
a command like `apt install` does exactly what it would do on a real rPi.

The reason two different docker images (dockcross and pimod) are used is that the former
contains cross-compilers while the latter uses QEMU emulation. This means that when compiling
programs using dockcross the compiler/link/etc run at full X64 speed and simply generate code
for ARM. While when running any command in pimod/QEMU there is a whole processor emulation layer
involved.

## Tips

- build the image by running `./build.sh` on a unixy system.
- refer to `.gihub/workflows/build.yml` for the exact process used by the automated build.
- to mount an image on linux using loop-back mounts:

```bash
  sudo losetup -f images/blah.img --show
  sudo kpartx -avs /dev/loopN
  sudo mount /dev/mapper/loopNp1 /mnt
```

- to enable the boot console on a CM3, add `console=serial0,115200` to the kernel command line in `/boot/cmdline.txt`.

## Keys to sign packages and update the debian repo

- TvE has the sensorgnome-repo key in his gpg keyring, it is encrypted using a password found
  in his password store
- The gpg key must be exported as ascii using

``` text
  gpg --list-secret-keys --keyid-format LONG; gpg --export-secret-keys --armor 11162C1D8661F9148480CDD98EFF151A5DDAE8F1
```

- The result must be set as `GPG_PRIVATE_KEY` secret in github, and the passphrase as `GPG_PASSPHRASE`
- To upload the package to S3, an AWS role must be configured to allow the github action to upload
- To extend the validity of the keys:

```
gpg --edit-key 11162C1D8661F9148480CDD98EFF151A5DDAE8F1
gpg> expire
gpg> key 1
gpg> expire
gpg> save
```
- To export the public key, which needs to be placed in /etc/apt/trusted.gpg.d/sensorgnome.gpg:

```
gpg --export 11162C1D8661F9148480CDD98EFF151A5DDAE8F1 >sensorgnome-pub-2024.gpg
```

## Sensorstation boot

- The jumper should be in the "enable USB boot" position
- To mount the SS EMMC: run rpiboot, plug the micro-USB in, then power on the SS
- To boot the SS normally: remove the micro-USB then power on the SS
- To see the boot console, use a USB-serial adapter on the rPi expansion connector at 115200
- If the console switches to NUL after the initial boot: that's gpsd trying to talk to a
  gps @9600 baud; this can be disabled in /opt/sensorgnome/gps-clock/init-adafruit-gps.sh
  
