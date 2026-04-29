#! /bin/bash -e
# Shell script to fix-up a Sensorgnome to use for development of sensorgnome-control

if [[ -z "$1" ]]; then
    echo "Usage: $0 <hostname>"
    exit 1
fi

ssh $1 hostname
rsync ~/.ssh/lberrigan-git2022 $1:.ssh/
ssh $1 'git config --global user.email "lberrigan@birdscanada.org"; git config --global user.name "Lucas Berrigan"'

ssh $1 "egrep -q github .ssh/config || tee -a .ssh/config" <<EOF >/dev/null
Host github.com
    User git
    Hostname github.com
    IdentityFile /home/gnome/.ssh/lberrigan-git2022
    StrictHostKeyChecking no
EOF

ssh $1 "test -d sensorgnome-control || git clone git@github.com:leberrigan/sensorgnome-control.git"
ssh $1 "ln -s /opt/sensorgnome/control/public/flexdash ~/sensorgnome-control/src/public"

ssh $1 "cat >sensorgnome-control/run; chmod +x sensorgnome-control/run" <<EOF
#! /bin/bash
cd /home/gnome/sensorgnome-control/src
export NODE_ENV=production
export NODE_PATH=/home/gnome/sensorgnome-control/src
export LC_ALL="C.UTF-8"
node main
EOF

ssh $1 "sudo -S bash -c 'systemctl stop sg-control; systemctl disable sg-control; sed -i -e 's/pi/gnome/' /etc/sudoers.d/010_pi-nopasswd'"

cat <<EOF

# Run the following manually:
cd sensorgnome-control
git checkout flexdash
cd src
npm install
EOF
