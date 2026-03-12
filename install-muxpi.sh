#!/bin/bash

# check connection 
echo -e "\n### check connection to GitHub.com ### \n"
if ! curl -s --head https://github.com | head -n 1 | grep "200" > /dev/null; then
    echo -e "\n### Unable to connect to GitHub.com ### "
    exit 1
fi

# install muxpi.sh to folder muxpi 
echo -e "\n ### download and install muxpi.sh ###\n"
mkdir -p muxpi 

# download muxpi  
cd muxpi  
curl -O https://raw.githubusercontent.com/ewaldj/muxpi/main/muxpi.sh
chmod +x muxpi.sh
cd ..
echo -e "\n### done - have a nice day - www.jeitler.guru ###\n" 
