#!/bin/bash

<<LICENSE
MIT License

Copyright (c) 2022 Laurent Baumann

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
LICENSE

# set -x

# Data files and folders
routeFile='source/_routes.conf'
dataFile='source/_data.conf'
templateDir='source'
outputDir='public'
assetDir='source/static'
postsDir='source/posts'
postTemplate='_post_template.html'

# Pandoc is the only dependency beyond GNU
# if ! command -v "pandoc" &> /dev/null; then
#     echo -e "🚨 Pandoc not installed!\n"
#     exit 1
# fi

# Support for macOS
# if [[ $OSTYPE == 'darwin'* ]]; then
#     if ! command -v "ggrep" &> /dev/null; then
#         if ! command -v "brew" &> /dev/null; then
#             echo -e "🚨 Brew not installed!\n"
#             exit 1
#         fi
#         brew install grep
#         alias grep=ggrep
#     fi
# fi

# Avoid "&" to be interpreted by bash
# Temporarely replaces & with {{and}}
# while we process all the template files.
# That avoid bash to interpret the & in our csv, md, or html files
replacementString="{{and}}"

function test {
    local result="$1"
    local empty=''

    result="${result//&/$replacementString}"

    OLDIFS="$IFS"
    IFS=$'\n'

    # Code here

    IFS="$OLDIFS"
    # echo -n -e "$result"
    echo -e "$result"
}


function prerenderTemplate {
    local TPLFILE="$1"
    local TPLCONTENT="$(<$TPLFILE)"
    local empty=''

    TPLCONTENT="${TPLCONTENT//&/$replacementString}"
    OLDIFS="$IFS"
    IFS=$'\n'

    # INCLUDES
    # Insert the content of a file into another
    # Most common case is to include footer, or navigation
    # Example: <!--#include:_include/_footer.html-->
    # ---------------------------------------------------------------
    # local INCLUDES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#include:.*}}')
    local INCLUDES=$(echo -n "$TPLCONTENT"|perl -nle 'print $& if m/\{\{\s*#include:.*}}/')

    for empty in $INCLUDES; do
        # local INCLFNAME=$(echo -n "$empty"|grep -Po '(?<=#include:).*?(?=}})')
        local INCLFNAME=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#include:).*?(?=}})/')

        local INCLFCONTENT="$(prerenderTemplate ${INCLFNAME})"
        # Escape & in the imported content since it's gonna be processed again
        # Might be irrelevant now that we replace all & at the beginning?
        INCLFCONTENT="${INCLFCONTENT//&/\\&}"
        TPLCONTENT="${TPLCONTENT//$empty/$INCLFCONTENT}"
    done

    # DATA MODULES
    # It currently break if you have more then one per page. Grep is not the right tool.
    # In your HTML markup, use <!--#module:test.csv#template:_include/_block.html-->
    # For each entry in the csv file, a module will be inserted inline.
    # The values in the csv are applied to the variabled in the template
    # For example, the values in the column "name" in the csv will remplate {{name}} templates
    # ---------------------------------------------------------------
    # local MODULES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#data:.*#template:.*}}')
    local MODULES=$(echo -n "$TPLCONTENT"|perl -nle 'print $& if m/\{\{\s*#data:.*#template:.*}}/')

    # local MODULES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#data:.*#template:.*#parent:.*}}')
    for empty in $MODULES; do
        # local MODDATA=$(echo -n "$empty"|grep -Po '(?<=#data:).*?(?=#template:)')
        local MODDATA=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#data:).*?(?=#template:)/')

        # local MODTPLT=$(echo -n "$empty"|grep -Po '(?<=#template:).*(?=}})')
        local MODTPLT=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#template:).*(?=}})/')

        # local MODTPLT=$(echo -n "$empty"|grep -Po '(?<=#template:).*?(?=#parent:)')
        # local parent=$(echo -n "$empty"|grep -Po '(?<=#parent:).*?(?=}})')

        # Load the data file (csv) and iterate over it
        local MODdataFile="${templateDir}/$MODDATA"
        local dataOutput="$(<$MODdataFile)"
        dataOutput="${dataOutput//&/$replacementString}"

        local MODTPLTFILE="${templateDir}/$MODTPLT"

        # Map the csv file to a 1D array, one row per line
        # IFS=$'\n' mapfile -t csvArray < $MODdataFile
        IFS=$'\n' mapfile -t csvArray < <(printf "$dataOutput")

        # Store the keys in an array for later (the first line of the csv file)
        IFS='|' read -ra keyArray <<< "${csvArray[0]}"

        # MODOUTPUT="<div class="$parent">"
        for ((i = 1; i < ${#csvArray[@]}; ++i)); do
            IFS='|' read -ra valuesArray <<< "${csvArray[$i]}"
            local templateOutput="$(<$MODTPLTFILE)"
            templateOutput="${templateOutput//&/$replacementString}"

            for ((j = 0; j < ${#valuesArray[@]}; ++j)); do
                templateOutput="${templateOutput//\{\{${keyArray[$j]}\}\}/${valuesArray[$j]}}"
            done
            MODOUTPUT+="$templateOutput"
        done
        # MODOUTPUT+="</div>"

        MODOUTPUT="${MODOUTPUT//$replacementString/&}"
        TPLCONTENT="${TPLCONTENT//$empty/$MODOUTPUT}"
    done

    # INLINE BASH
    # Use to run bash inline: <!--#bash:echo Hello World!-->
    # Can be used in footer for copyright info for example
    # <!--#bash:date +"%Y"--> — All Rights Reserved
    # ---------------------------------------------------------------
    # local SCRIPTS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#bash:.*}}')
    local SCRIPTS=$(echo -n "$TPLCONTENT"|perl -nle 'print $& if m/\{\{\s*#bash:.*}}/')

    for empty in $SCRIPTS; do
        # local COMMAND=$(echo -n "$empty"|grep -Po '(?<=#bash:).*?(?=}})')
        local COMMAND=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#bash:).*?(?=}})/')

        local OUTPUTCONTENT=$(eval $COMMAND)
        TPLCONTENT="${TPLCONTENT//$empty/$OUTPUTCONTENT}"
    done

    # POSTS LIST
    # List of all the posts in the folder defined as postsDir as a <ul>
    # Example: {{#posts:0}}
    # ---------------------------------------------------------------
    # local POSTS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#posts:.*}}')
    local POSTS=$(echo -n "$TPLCONTENT"|perl -nle 'print $& if m/\{\{\s*#posts:.*}}/')

    for empty in $POSTS; do
        local POSTSLISTCONTENT=""
        # local postCount=$(echo -n "$empty"|grep -Po '(?<=#posts:).*?(?=}})')
        local postCount=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#posts:).*?(?=}})/')

        local iteration=0
        # echo $postCount
        for folder in "$postsDir"/*
        do
            if [[ -d $folder ]]; then
                # if a limiter is passed as {{#posts:3}} for the most recent 3 posts
                if((postCount != 0)); then
                    if ((iteration >= $postCount)); then
                        break  # Exit the loop when the maximum iterations are reached
                    fi
                    ((iteration++))
                fi

                # Extract the file name
                file_name=$(basename -- "$folder")

                # Extract frontmatter & remove the first and last lines (---)
                # frontmatter=$(sed -n '/---/,/---/p' "$postsDir/$file_name/article.md" | sed '1d;$d')
                #
                # # The array holding the frontmatter variables
                # declare -A data
                #
                # while IFS= read -r line; do
                #     # Extract key and value, splitting by ":"
                #     IFS=":" read -r key value <<< "$line"
                #
                #     # Trim leading and trailing whitespace from the key and value
                #     key=$(echo "$key" | xargs)
                #     value=$(echo "$value" | xargs)
                #
                #     # Store the key-value pair in the associative array
                #     data["$key"]="$value"
                # done <<< "$frontmatter"



                local post_string="$(<'source/_include/_post.html')"
                link="/posts/$file_name/"
                # preview="/posts/$file_name/${data[preview]}"

                POSTDATA="$(<"$folder/article.conf")"
                for DATA in $POSTDATA; do
                    DATANAME="${DATA%%:*}"
                    DATANAME=$(echo "$DATANAME" | xargs)
                    DATAVAL="${DATA#*:}"
                    DATAVAL=$(echo "$DATAVAL" | xargs)
                    if [ "$DATANAME" == "preview" ]; then
                        DATAVAL="/posts/$file_name/${DATAVAL}"
                    fi
                    post_string="${post_string//\{\{${DATANAME}\}\}/${DATAVAL}}"
                done


                # post_string="${post_string//\{\{title\}\}/${data[title]}}"
                # post_string="${post_string//\{\{author\}\}/${data[author]}}"
                # post_string="${post_string//\{\{date\}\}/${data[date]}}"
                # post_string="${post_string//\{\{description\}\}/${data[desc]}}"
                # post_string="${post_string//\{\{previewImage\}\}/${previewURL}}"
                post_string="${post_string//\{\{link\}\}/${link}}"

                POSTSLISTCONTENT="$POSTSLISTCONTENT\n$post_string"
            fi

        done
        POSTSLISTCONTENT="$POSTSLISTCONTENT\n"
        TPLCONTENT="${TPLCONTENT//$empty/$POSTSLISTCONTENT}"
    done


    # MARKDOWN
    # Render markdown file inline
    # Example: <!--#markdown:README.md-->
    # ---------------------------------------------------------------
    # local MDS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#markdown:.*}}')
    local MDS=$(echo -n "$TPLCONTENT"|perl -nle 'print $& if m/\{\{\s*#markdown:.*}}/')
    for empty in $MDS; do
        # local MDNAME=$(echo -n "$empty"|grep -Po '(?<=#markdown:).*?(?=}})')
        # local MDS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#markdown:.*}}')
        local MDNAME=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#markdown:).*?(?=}})/')

        # local MDCONTENT="$(pandoc --columns 100 ${MDNAME})"
        local MDCONTENT="$(perl markdown.pl --html4tags ${MDNAME})"
        MDCONTENT="${MDCONTENT//&/$replacementString}"
        TPLCONTENT="${TPLCONTENT//$empty/$MDCONTENT}"
    done

    IFS="$OLDIFS"
    # echo -n -e "$TPLCONTENT"
    echo -e "$TPLCONTENT"
}

function renderTemplate {
    local TPLTEXT="$(prerenderTemplate $1)"

    # Local variables with <!--#set-->
    # local SETS=$(echo -n "$TPLTEXT"|grep -Po '{{#set:.*?}}')
    # local MDS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#markdown:.*}}')
    local SETS=$(echo -n "$TPLTEXT"|perl -nle 'print $& if m/\{\{#set:.*?}}/')

    local L=''
    OLDIFS="$IFS"
    IFS=$'\n'
    for L in $SETS; do
        # local SET=$(echo -n "$L"|grep -Po '(?<=#set:).*?(?=}})')
        local SET=$(echo -n "$L"|perl -nle 'print $& if m/(?<=#set:).*?(?=}})/')

        local SETVAR="${SET%%=*}"
        local SETVAL="${SET#*=}"
        TPLTEXT="${TPLTEXT//$L/}"
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
    TPLTEXT="${TPLTEXT//$replacementString/\&amp;}"

    # remove empty lines
    # local TPLTEXT=$(echo -n "$TPLTEXT"|grep -v '^$')
    # local TPLTEXT=$(echo -n "$TPLTEXT"|perl -nle 'print $& if m/^$/')

    IFS="$OLDIFS"
    # echo -n -e "$TPLTEXT"
    echo -e "$TPLTEXT"
}

#run main action
mkdir -p "$outputDir"
rm -rf "${outputDir}"/*
echo -e "🧹 Cleaned up $(tput bold)/$outputDir/$(tput sgr0) folder"
if [[ "$assetDir" ]]; then
    # cp -rd "$assetDir" "${outputDir}/"
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
        # converted_markdown="$(pandoc --columns 100 "$folder/article.md")"
        converted_markdown="$(perl markdown.pl --html4tags "$folder/article.md")"

        # local MDCONTENT="$(perl markdown.pl --html4tags ${MDNAME})"
        converted_markdown="${converted_markdown//&/$replacementString}"

        # echo $converted_markdown
        # Grab the template and replace {{#slot}} with the generate html
        templateOutput="$(<"$templateDir/$postTemplate")"
        templateOutput="${templateOutput//\{\{#slot\}\}/${converted_markdown}}"

        # Include code copied from render function
        # TODO: isolate in it's own function
        # INCLUDES=$(echo -n "$templateOutput"|grep -Po '{{\s*#include:.*}}')
        INCLUDES=$(echo -n "$templateOutput"|perl -nle 'print $& if m/\{\{\s*#include:.*}}/')

        for empty in $INCLUDES; do
            # INCLFNAME=$(echo -n "$empty"|grep -Po '(?<=#include:).*?(?=}})')
            INCLFNAME=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#include:).*?(?=}})/')
            INCLFCONTENT="$(prerenderTemplate ${INCLFNAME})"
            # Escape & in the imported content since it's gonna be processed again
            # Might be irrelevant now that we replace all & at the beginning?
            INCLFCONTENT="${INCLFCONTENT//&/\\&}"
            templateOutput="${templateOutput//$empty/$INCLFCONTENT}"
        done

        # TODO: This code is duplicated from the render function
        # All those functions (bash, markdown, include) should be isolated
        # SCRIPTS=$(echo -n "$templateOutput"|grep -Po '{{\s*#bash:.*}}')
        SCRIPTS=$(echo -n "$templateOutput"|perl -nle 'print $& if m/\{\{\s*#bash:.*}}/')

        for empty in $SCRIPTS; do
            # COMMAND=$(echo -n "$empty"|grep -Po '(?<=#bash:).*?(?=}})')
            COMMAND=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#bash:).*?(?=}})/')

            OUTPUTCONTENT=$(eval $COMMAND)
            templateOutput="${templateOutput//$empty/$OUTPUTCONTENT}"
        done

        # SETS=$(echo -n "$templateOutput"|grep -Po '{{#set:.*?}}')
        SETS=$(echo -n "$templateOutput"|perl -nle 'print $& if m/\{\{#set:.*?}}/')

        # Local variables with <!--#set-->
        for empty in $SETS; do
            # local SET=$(echo -n "$empty"|grep -Po '(?<=#set:).*?(?=}})')
            local SET=$(echo -n "$empty"|perl -nle 'print $& if m/(?<=#set:).*?(?=}})/')

            local SETVAR="${SET%%=*}"
            local SETVAL="${SET#*=}"
            templateOutput="${templateOutput//$empty/}"
            templateOutput="${templateOutput//\{\{${SETVAR}\}\}/${SETVAL}}"
        done

        # Global variables from the dataFile
        DATALIST="$(<$dataFile)"
        for DATA in $DATALIST; do
            DATANAME="${DATA%%:*}"
            DATAVAL="${DATA#*:}"
            templateOutput="${templateOutput//\{\{${DATANAME}\}\}/${DATAVAL}}"
        done

        # Article variables from the article.conf file
        POSTDATA="$(<"$folder/article.conf")"
        for DATA in $POSTDATA; do
            DATANAME="${DATA%%:*}"
            DATAVAL="${DATA#*:}"
            templateOutput="${templateOutput//\{\{${DATANAME}\}\}/${DATAVAL}}"
        done

        # # Extract frontmatter & remove the first and last lines (---)
        # frontmatter=$(sed -n '/---/,/---/p' "$folder/article.md" | sed '1d;$d')
        #
        # # The array holding the frontmatter variables
        # declare -A data
        #
        # while IFS= read -r line; do
        #     # Extract key and value, splitting by ":"
        #     IFS=":" read -r key value <<< "$line"
        #
        #     # Trim leading and trailing whitespace from the key and value
        #     key=$(echo "$key" | xargs)
        #     value=$(echo "$value" | xargs)
        #
        #     echo "$key: $value"
        #
        #     # Store the key-value pair in the associative array
        #     data["$key"]="$value"
        # done <<< "$frontmatter"

        # previewURL="posts/$folder_name/${data[preview]}"
        # templateOutput="${templateOutput//\{\{title\}\}/${data[title]}}"
        # templateOutput="${templateOutput//\{\{description\}\}/${data[desc]}}"
        # templateOutput="${templateOutput//\{\{previewImage\}\}/${previewURL}}"

        # Copy the folder, since it might contain assets
        # cp -rd "$folder" "${outputDir}/posts/"
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

IFS="$OLDIFS"
echo -e "🎀 The website is ready!\n"
