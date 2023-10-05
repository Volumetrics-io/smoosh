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

# This script only works with GNU sed. So if you have both BSD sed
# and GNU sed installed (often happens on OSX), you will need to alias GNU sed.
# If you get the error "sed: illegal option -- r", you will need to apply this fix.
# shopt -s expand_aliases
# alias sed=gsed

# set -x

# Data files and folders
routeFile='source/_routes.conf'
dataFile='source/_data.conf'
templateDir='source'
outputDir='public'
assetDir='source/static'
postsDir='source/posts'
postTemplateHeader='_post_header.html'
postTemplateFooter='_post_footer.html'

# Pandoc is the only dependency beyond GNU
if ! command -v "pandoc" &> /dev/null; then
    echo -e "🚨 Pandoc not installed!\n"
    exit 1
fi

# Support for macOS
if [[ $OSTYPE == 'darwin'* ]]; then
    if ! command -v "ggrep" &> /dev/null; then
        if ! command -v "brew" &> /dev/null; then
            echo -e "🚨 Brew not installed!\n"
            exit 1
        fi
        brew install grep
        alias grep=ggrep
    fi
fi

# Avoid "&" to be interpreted by bash
# Generate a random remplacement string to temporarely replace
# the & character while we process all the template files.
# That avoid bash to interpret the & in our csv, md, or html files
# replacementString=$(echo $RANDOM | md5sum | head -c 20; echo;)
replacementString="{{and}}"

function prerenderTemplate {
    local TPLFILE="${templateDir}/$1"
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
    local INCLUDES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#include:.*}}')
    for empty in $INCLUDES; do
        local INCLFNAME=$(echo -n "$empty"|grep -Po '(?<=#include:).*?(?=}})')
        local INCLFCONTENT="$(prerenderTemplate ${INCLFNAME})"
        # Escape & in the imported content since it's gonna be processed again
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
    local MODULES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#data:.*#template:.*}}')
    # local MODULES=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#data:.*#template:.*#parent:.*}}')
    for empty in $MODULES; do
        local MODDATA=$(echo -n "$empty"|grep -Po '(?<=#data:).*?(?=#template:)')
        local MODTPLT=$(echo -n "$empty"|grep -Po '(?<=#template:).*(?=}})')
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
    local SCRIPTS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#bash:.*}}')
    for empty in $SCRIPTS; do
        local COMMAND=$(echo -n "$empty"|grep -Po '(?<=#bash:).*?(?=}})')
        local OUTPUTCONTENT=$(eval $COMMAND)
        TPLCONTENT="${TPLCONTENT//$empty/$OUTPUTCONTENT}"
    done

    # POSTS LIST
    # List of all the posts in the folder defined as postsDir as a <ul>
    # Example: {{#posts:0}}
    # ---------------------------------------------------------------
    local POSTS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#posts:.*}}')
    for empty in $POSTS; do
        local POSTSLISTCONTENT="<ul>"
        local postCount=$(echo -n "$empty"|grep -Po '(?<=#posts:).*?(?=}})')
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
                # Remove the extension. This is our route (slug)
                # slug="$(echo "${file_name%.*}")"

                # Extract frontmatter & remove the first and last lines (---)
                frontmatter=$(sed -n '/---/,/---/p' "$postsDir/$file_name/article.md" | sed '1d;$d')

                # The array holding the frontmatter variables
                declare -A data

                while IFS= read -r line; do
                    # Extract key and value, splitting by ":"
                    IFS=":" read -r key value <<< "$line"

                    # Trim leading and trailing whitespace from the key and value
                    key=$(echo "$key" | xargs)
                    value=$(echo "$value" | xargs)

                    # Store the key-value pair in the associative array
                    data["$key"]="$value"
                done <<< "$frontmatter"

                local li_string="<li><img src='/posts/$file_name/${data[preview]}' style='width: 100px' /><a href='/posts/$file_name/'>${data[title]}</a> by ${data[author]} on ${data[date]}</li>\n"
                POSTSLISTCONTENT="$POSTSLISTCONTENT\n$li_string"
            fi

        done
        POSTSLISTCONTENT="$POSTSLISTCONTENT\n</ul>"
        TPLCONTENT="${TPLCONTENT//$empty/$POSTSLISTCONTENT}"
    done


    # MARKDOWN
    # Render markdown file inline
    # Example: <!--#markdown:README.md-->
    # ---------------------------------------------------------------
    local MDS=$(echo -n "$TPLCONTENT"|grep -Po '{{\s*#markdown:.*}}')
    for empty in $MDS; do
        local MDNAME=$(echo -n "$empty"|grep -Po '(?<=#markdown:).*?(?=}})')
        local MDCONTENT="$(pandoc --columns 100 ${MDNAME})"
        MDCONTENT="${MDCONTENT//&/$replacementString}"
        TPLCONTENT="${TPLCONTENT//$empty/$MDCONTENT}"
    done

    IFS="$OLDIFS"
    echo -n -e "$TPLCONTENT"
}

function renderTemplate {
    local TPLTEXT="$(prerenderTemplate $1)"
    local SETS=$(echo -n "$TPLTEXT"|grep -Po '{{#set:.*?}}')
    local L=''
    OLDIFS="$IFS"
    IFS=$'\n'

    # Local variables with <!--#set-->
    for L in $SETS; do
        local SET=$(echo -n "$L"|grep -Po '(?<=#set:).*?(?=}})')
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
    local TPLTEXT=$(echo -n "$TPLTEXT"|grep -v '^$')

    IFS="$OLDIFS"
    echo -n -e "$TPLTEXT"
}

#run main action
mkdir -p "$outputDir"
rm -rf "${outputDir}"/*
echo -e "🧹 Cleaned up $(tput bold)/$outputDir/$(tput sgr0) folder"
if [[ "$assetDir" ]]; then
    cp -rd "$assetDir" "${outputDir}/"
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
        # Remove the extension. This is our route (slug)
        # slug="$(echo "${file_name%.*}")"
        # Convert the markdown to HTML
        converted_markdown="$(pandoc --columns 100 "$folder/article.md")"

        # postTemplateHeader
        templateHeader="$(<"$templateDir/$postTemplateHeader")"
        # templateHeader="$(renderTemplate ${postTemplateHeader})"
        # templateHeader="${templateHeader//&/$replacementString}"

        templateFooter="$(<$templateDir/$postTemplateFooter)"
        # templateFooter="${templateFooter//&/$replacementString}"

        output="$templateHeader$converted_markdown$templateFooter"

        # mkdir -p "$outputDir/posts/$slug"
        cp -rd "$folder" "${outputDir}/posts/"

        echo $output > "${outputDir}/posts/${folder_name}/index.html"
        # renderTemplate "${outputDir}/posts/${folder_name}/template.html" > "${outputDir}/posts/${folder_name}/index.html"

        echo "🐥 Generated blog post $(tput bold)$folder$(tput sgr0)"
        # echo "🐥 Generated blog post $(tput bold)$slug$(tput sgr0)"
    fi

    # TODO: Add the opengraph
    # TODO: Sandwitch markup with nav and footer
    # TODO: Generate RSS Feed
done

for ROUTE in $ROUTELIST; do
    TPLNAME="${ROUTE%%:*}"
    TPLPATH="${ROUTE#*:}"
    if [[ "$TPLNAME" && "$TPLPATH" ]]; then
        mkdir -p "${outputDir}${TPLPATH}"
        renderTemplate "$TPLNAME" > "${outputDir}${TPLPATH}index.html"
        chars=✨🌟⭐💫
        emoji="${chars:RANDOM%${#chars}:1}"
        echo "$emoji Rendered $TPLNAME to $(tput bold)$TPLPATH$(tput sgr0)"
    fi
done

IFS="$OLDIFS"
echo -e "🎀 The website is ready!\n"
