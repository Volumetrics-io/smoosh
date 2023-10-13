#!/bin/bash

# MIT License
#
# Copyright (c) 2022 Laurent Baumann
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Data files and folders
routeFile='source/_routes.conf'
dataFile='source/_data.conf'
templateDir='source'
outputDir='public'
assetDir='source/static'
postsDir='source/posts'
postTemplate='_post_template.html'

# Website data for generated RSS feed
feedTitle='Volumetrics Blog'
feedURL='https://volusmoosh.onrender.com'
feedDescription='Follow our progress while we’re building.'

# Check if rsync is available
if ! command -v rsync > /dev/null; then
      echo -e "🚨 rsync is not installed!\n"
    exit 1
fi

# Avoid "&" to be interpreted by bash
# Temporarely replaces & with %and% while we process all the template files.
# That avoid bash to interpret the & in our csv, md, or html files
replacementString="%and%"

function generatePostList {
    OLDIFS="$IFS"
    IFS=$'\n'

    # POSTS LIST
    # List of all the posts in the folder defined as postsDir as a <ul>
    # Example: {{#posts:0}}
    # ---------------------------------------------------------------
    local postCount="$1"
    local empty=''
    local result=""
    local iteration=0

    # Initialize an associative array
    declare -A posts

    # Step 1 and 2: Extract dates and associate them with folders
    for folder in "$postsDir"/*
    do
    if [[ -d $folder && -f "$folder/article.conf" ]]; then
            # Extract the date from article.conf
            # date=$(grep -E '^date:' "$folder/article.conf" | cut -d':' -f2 | xargs)
            date=$(perl -ne '/^date:\s*(.+)/ && print $1' "$folder/article.conf")

            # Store the folder path, associated with its date
            posts["$date"]="$folder"
        fi
    done

    # Step 3: Sort dates and get them in an array
    sorted_dates=( $(for date in "${!posts[@]}"; do echo "$date"; done | sort -r) )

    # Step 4: Generate the articles in the sorted order
    for date in "${sorted_dates[@]}"
    do
        if((postCount != 0)); then
            if ((iteration >= $postCount)); then
                break  # Exit the loop when the maximum iterations are reached
            fi
            ((iteration++))
        fi

        folder="${posts[$date]}"

        # Extract the file name
        folder_name=$(basename -- "$folder")

        # Load the post template
        local post_string="$(<'source/_include/_post.html')"
        link="/posts/$folder_name/"


        # Load the article metadata and smoosh them with the template
        POSTDATA="$(<"$folder/article.conf")"
        for DATA in $POSTDATA; do
            DATANAME="${DATA%%:*}"
            DATANAME=$(echo "$DATANAME" | xargs)
            DATAVAL="${DATA#*:}"
            DATAVAL=$(echo "$DATAVAL" | xargs)
            if [ "$DATANAME" == "preview" ]; then
                DATAVAL="/posts/$folder_name/${DATAVAL}"
            fi
            if [ "$DATANAME" == "date" ]; then
                # DATAVAL=$(date -d ${DATAVAL} '+%A %B %d, %Y')
                DATAVAL=$(date -d ${DATAVAL} '+%b %d, %Y')
            fi
            post_string="${post_string//\{\{${DATANAME}\}\}/${DATAVAL}}"
        done

        post_string="${post_string//\{\{link\}\}/${link}}"
        result="$result\n$post_string"
    done

  result="$result\n"

  IFS="$OLDIFS"
  echo -e "$result"
}

function trim {
    local var="$*"
    # remove leading whitespace characters
    var="${var#"${var%%[![:space:]]*}"}"
    # remove trailing whitespace characters
    var="${var%"${var##*[![:space:]]}"}"
    printf '%s' "$var"
}

function generateFeed {

    # Initialize an associative array
    declare -A posts

    # Step 1 and 2: Extract dates and associate them with folders
    for folder in "$postsDir"/*
    do
    if [[ -d $folder && -f "$folder/article.conf" ]]; then
            # Extract the date from article.conf
            date=$(perl -ne '/^date:\s*(.+)/ && print $1' "$folder/article.conf")

            # Store the folder path, associated with its date
            posts["$date"]="$folder"
        fi
    done

    # Step 3: Sort dates and get them in an array
    sorted_dates=( $(for date in "${!posts[@]}"; do echo "$date"; done | sort -r) )

    feedFile="${outputDir}/feed.xml"

    # Output RSS header
    echo '<?xml version="1.0" encoding="UTF-8" ?>' > $feedFile
    echo '<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/">' >> $feedFile
    echo '<channel>' >> $feedFile
    echo "    <title>${feedTitle}</title>" >> $feedFile
    echo "    <link>${feedURL}</link>" >> $feedFile
    echo "    <description>${feedDescription}</description>" >> $feedFile
    echo '    <language>en-us</language>' >> $feedFile
    echo '    <pubDate>'$(date -R)'</pubDate>' >> $feedFile

    # Generate items in RSS feed
    for date in "${sorted_dates[@]}"
    do
        folder="${posts[$date]}"
        POSTDATA="$(<"$folder/article.conf")"

        # Extract the file name
        folder_name=$(basename -- "$folder")

        # Initialize empty variables to avoid using old data
        title=""
        description=""
        link=""
        pubDate=""

        # Extract data for each article
        for DATA in $POSTDATA; do
            DATANAME="${DATA%%:*}"
            DATAVAL="${DATA#*:}"
            # Use the data to generate RSS item
            case "$DATANAME" in
                title) title="$(trim "${DATAVAL}")" ;;
                description) description="$(trim "${DATAVAL}")" ;;
                preview) preview="$(trim "${DATAVAL}")" ;;
                author) author="$(trim "${DATAVAL}")" ;;
                # Add any other data fields you want to extract here...
            esac
        done

        # Extract the content of the markdown file
        # content="$(<"$folder/article.md")"

        content="$(perl markdown.pl --html4tags "$folder/article.md")"

        # Escape some XML special characters & < >
        baseImagePath="${feedURL}/posts/${folder_name}/"
        content="${content//<img src=\"/<img src=\"${baseImagePath}}"
        # content="${content//</&lt;}"
        # content="${content//>/&gt;}"


        # Generate the RSS item XML
        echo '    <item>' >> $feedFile
        echo "        <title>${title}</title>" >> $feedFile
        echo "        <link>${feedURL}/posts/${folder_name}/</link>" >> $feedFile
        echo "        <description><![CDATA[<img src='${feedURL}/posts/${folder_name}/${preview}' /><p>${description}</p>]]></description>" >> $feedFile
        echo "        <content:encoded><![CDATA[${content}]]></content:encoded>" >> $feedFile
        echo "        <pubDate>$(date -R -d"$date")</pubDate>" >> $feedFile
        echo '    </item>' >> $feedFile
    done

    # Output RSS footer
    echo '</channel>' >> $feedFile
    echo '</rss>' >> $feedFile

    echo "📣 Generated RSS Feed"
}

function prerenderTemplate {
    local templateFile="$1"
    local templateContent="$(<$templateFile)"
    local empty=''

    templateContent="${templateContent//&/$replacementString}"
    OLDIFS="$IFS"
    IFS=$'\n'

    # INCLUDES
    # Insert the content of a file into another
    # Example: <!--#include:_include/_footer.html-->
    # ---------------------------------------------------------------
    local INCLUDES=$(echo -n "$templateContent"|perl -nle 'print $& if m/\{\{\s*#include:.*}}/')

    for empty in $INCLUDES; do
        local INCLFNAME=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#include:).*?(?=}})/')
        local INCLFCONTENT="$(prerenderTemplate ${INCLFNAME})"
        # Escape & in the imported content since it's gonna be processed again
        # INCLFCONTENT="${INCLFCONTENT//&/$replacementString}"
        templateContent="${templateContent//$empty/$INCLFCONTENT}"
    done

    # DATA MODULES
    # It currently break if you have more then one per page. Grep is not the right tool.
    # In your HTML markup, use <!--#module:test.csv#template:_include/_block.html-->
    # For each entry in the csv file, a module will be inserted inline.
    # The values in the csv are applied to the variabled in the template
    # For example, the values in the column "name" in the csv will remplate {{name}} templates
    # ---------------------------------------------------------------
    local MODULES=$(echo -n "$templateContent"|perl -nle 'print $& if m/\{\{\s*#data:.*#template:.*}}/')

    for empty in $MODULES; do
        local MODDATA=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#data:).*?(?=#template:)/')
        local MODTPLT=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#template:).*(?=}})/')

        # Load the data file (csv) and iterate over it
        local MODdataFile="${templateDir}/$MODDATA"
        local dataOutput="$(<$MODdataFile)"
        dataOutput="${dataOutput//&/$replacementString}"

        local MODTPLTFILE="${templateDir}/$MODTPLT"

        # Map the csv file to a 1D array, one row per line
        IFS=$'\n' mapfile -t csvArray < <(printf "$dataOutput")

        # Store the keys in an array for later (the first line of the csv file)
        IFS='|' read -ra keyArray <<< "${csvArray[0]}"

        for ((i = 1; i < ${#csvArray[@]}; ++i)); do
            IFS='|' read -ra valuesArray <<< "${csvArray[$i]}"
            local templateOutput="$(<$MODTPLTFILE)"
            templateOutput="${templateOutput//&/$replacementString}"

            for ((j = 0; j < ${#valuesArray[@]}; ++j)); do
                templateOutput="${templateOutput//\{\{${keyArray[$j]}\}\}/${valuesArray[$j]}}"
            done
            MODOUTPUT+="$templateOutput"
        done

        MODOUTPUT="${MODOUTPUT//$replacementString/&}"
        templateContent="${templateContent//$empty/$MODOUTPUT}"
    done

    # INLINE BASH
    # Use to run bash inline: <!--#bash:echo Hello World!-->
    # Can be used in footer for copyright info for example
    # <!--#bash:date +"%Y"--> — All Rights Reserved
    # ---------------------------------------------------------------
    local SCRIPTS=$(echo -n "$templateContent"|perl -nle 'print $& if m/\{\{\s*#bash:.*}}/')

    for empty in $SCRIPTS; do
        local COMMAND=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#bash:).*?(?=}})/')

        local OUTPUTCONTENT=$(eval $COMMAND)
        templateContent="${templateContent//$empty/$OUTPUTCONTENT}"
    done

    # POSTS LIST
    # List of all the posts in the folder defined as postsDir as a <ul>
    # Example: {{#posts:0}}
    # ---------------------------------------------------------------
    local posts=$(echo -n "$templateContent"|perl -nle 'print $& if m/\{\{\s*#posts:.*}}/')
    for empty in $posts; do
        local postCount=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#posts:).*?(?=}})/')
        templateContent="${templateContent//$empty/$(generatePostList ${postCount})}"
    done

    # MARKDOWN
    # Render markdown file inline
    # Example: <!--#markdown:README.md-->
    # ---------------------------------------------------------------
    local MDS=$(echo -n "$templateContent"|perl -nle 'print $& if m/\{\{\s*#markdown:.*}}/')
    for empty in $MDS; do
        local MDNAME=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#markdown:).*?(?=}})/')
        local MDCONTENT="$(perl markdown.pl --html4tags ${MDNAME})"
        MDCONTENT="${MDCONTENT//&/$replacementString}"
        templateContent="${templateContent//$empty/$MDCONTENT}"
    done

    IFS="$OLDIFS"
    echo -e "$templateContent"
}

function renderTemplate {
    local TPLTEXT="$(prerenderTemplate $1)"
    OLDIFS="$IFS"
    IFS=$'\n'

    # Local variables with <!--#set-->
    local SETS=$(echo -n "$TPLTEXT"|perl -nle 'print $& if m/\{\{#set:.*?}}/')
    local empty=''
    for empty in $SETS; do
        local SET=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#set:).*?(?=}})/')
        local SETVAR="${SET%%=*}"
        local SETVAL="${SET#*=}"
        TPLTEXT="${TPLTEXT//$empty/}"
        TPLTEXT="${TPLTEXT//\{\{${SETVAR}\}\}/${SETVAL}}"
    done

    # Global variables from the dataFile
    DATALIST="$(<$dataFile)"
    for DATA in $DATALIST; do
        DATANAME="${DATA%%:*}"
        DATAVAL="${DATA#*:}"
        TPLTEXT="${TPLTEXT//\{\{${DATANAME}\}\}/${DATAVAL}}"
    done

    # Put back the &
    TPLTEXT="${TPLTEXT//$replacementString/\&}"

    # remove empty lines
    # local TPLTEXT=$(echo -n "$TPLTEXT"|grep -v '^$')
    # local TPLTEXT=$(echo -n "$TPLTEXT"|perl -nle 'print $& if m/^$/')

    IFS="$OLDIFS"
    echo -e "$TPLTEXT"
}

#run main action
mkdir -p "$outputDir"
rm -rf "${outputDir}"/*
echo -e "🧹 Cleaned up $(tput bold)/$outputDir/$(tput sgr0) folder"
if [[ "$assetDir" ]]; then
    rsync -a "$assetDir" "${outputDir}/"
    echo "📦️ Copied $(tput bold)/$assetDir/$(tput sgr0) assets folder"
fi
ROUTELIST="$(<$routeFile)"
OLDIFS="$IFS"
IFS=$'\n'


# Generate the blog posts
mkdir -p "$outputDir/posts/"
for folder in "$postsDir"/*
do
    if [[ -d $folder ]]; then
        # Extract the file name
        folder_name=$(basename -- "$folder")

        # Convert the markdown to HTML
        converted_markdown="$(perl markdown.pl --html4tags "$folder/article.md")"
        converted_markdown="${converted_markdown//&amp;/$replacementString}"
        converted_markdown="${converted_markdown//&/$replacementString}"

        # Grab the template and replace {{#slot}} with the generate html
        # templateOutput="$(<"$templateDir/$postTemplate")"
        templateOutput="$(prerenderTemplate "$templateDir/$postTemplate")"

        # Slot the rendered markdown in the {{slot}} of the template
        templateOutput="${templateOutput//\{\{#slot\}\}/${converted_markdown}}"

        # Local variables with <!--#set-->
        SETS=$(echo -n "$templateOutput"|perl -nle 'print $& if m/\{\{#set:.*?}}/')
        for empty in $SETS; do
            SET=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#set:).*?(?=}})/')
            SETVAR="${SET%%=*}"
            SETVAL="${SET#*=}"
            templateOutput="${templateOutput//$empty/}"
            templateOutput="${templateOutput//\{\{${SETVAR}\}\}/${SETVAL}}"
        done

        # Article variables from the article.conf file
        POSTDATA="$(<"$folder/article.conf")"
        for DATA in $POSTDATA; do
            DATANAME="${DATA%%:*}"
            DATANAME=$(echo "$DATANAME" | xargs)
            DATAVAL="${DATA#*:}"
            DATAVAL=$(echo "$DATAVAL" | xargs)
            if [ "$DATANAME" == "preview" ]; then
                DATAVAL="posts/$folder_name/${DATAVAL}"
            fi
            templateOutput="${templateOutput//\{\{${DATANAME}\}\}/${DATAVAL}}"
        done

        # Global variables from the dataFile
        DATALIST="$(<$dataFile)"
        for DATA in $DATALIST; do
            DATANAME="${DATA%%:*}"
            DATAVAL="${DATA#*:}"
            templateOutput="${templateOutput//\{\{${DATANAME}\}\}/${DATAVAL}}"
        done

        # Put back the &
        templateOutput="${templateOutput//$replacementString/\&}"

        # Copy the folder, since it might contain assets
        rsync -a "$folder" "${outputDir}/posts/"
        echo $templateOutput > "${outputDir}/posts/${folder_name}/index.html"

        chars=🎄🌲🌳🌴🎋🌿🪴🌱🍀
        emoji="${chars:RANDOM%${#chars}:1}"
        echo "$emoji Generated blog post $(tput bold)$folder_name$(tput sgr0)"
    fi

    # TODO: Generate RSS Feed
done

for ROUTE in $ROUTELIST; do
    TPLNAME="${ROUTE%%:*}"
    TPLPATH="${ROUTE#*:}"
    if [[ "$TPLNAME" && "$TPLPATH" ]]; then
        mkdir -p "${outputDir}${TPLPATH}"
        renderTemplate "$templateDir/$TPLNAME" > "${outputDir}${TPLPATH}index.html"
        chars=✨🌟⭐💫
        emoji="${chars:RANDOM%${#chars}:1}"
        echo "$emoji Rendered $TPLNAME to $(tput bold)$TPLPATH$(tput sgr0)"
    fi
done

generateFeed

IFS="$OLDIFS"
echo -e "🎀 The website is ready!\n"
