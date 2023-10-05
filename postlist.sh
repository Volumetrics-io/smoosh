#!/bin/bash
# set -x
postsDir='source/posts'

POSTSLISTCONTENT="<ul>"
for file in "$postsDir"/*
do
    # Extract the file name
    file_name=$(basename -- "$file")
    POSTSLISTCONTENT="$POSTSLISTCONTENT\n<li>$file_name</li>\n"
done

POSTSLISTCONTENT="$POSTSLISTCONTENT\n</ul>"
echo $POSTSLISTCONTENT
