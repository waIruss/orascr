
#!/bin/bash

#echo "Destination folder:"
#read dest
#echo $dest
dest_dir=~/patches

if [ -d "$dest_dir" ];
then
echo "destination exists"
else mkdir ~/patches
fi

if [ $# -eq 0 ]
then
        echo "No arguments supplied"
fi

for var in "$@"
do
        wget -P $dest_dir --http-user=jacek.rak@avantis.pl --http-passwd=duke8421 https://getupdates.oracle.com/all_unsigned/"$var" -O "$dest_dir/$var"

done


