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

# Avoid "&" to be interpreted by bash
# Generate a random remplacement string to temporarely replace
# the & character while we process all the template files.
# That avoid bash to interpret the & in our csv, md, or html files
replacementString=$(echo $RANDOM | md5sum | head -c 20; echo;)

function prerenderTemplate {
    local TPLFILE="${templateDir}/$1"
    local TPLCONTENT="$(<$TPLFILE)"
    
    TPLCONTENT="${TPLCONTENT//&/$replacementString}"
    OLDIFS="$IFS"
    IFS=$'\n'
    
    # INCLUDES
    # Insert the content of a file into another
    # Most common case is to include footer, or navigation
    # Example: <!--#include:_include/_footer.html-->
    # ---------------------------------------------------------------
    local empty=''
    local INCLUDES=$(grep -Po '{{\s*#include:.*}}' "$TPLFILE")
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
    local MODULES=$(grep -Po '{{\s*#data:.*:.*}}' "$TPLFILE")
    for empty in $MODULES; do
        local MODDATA=$(echo -n "$empty"|grep -Po '(?<=#data:).*?(?=#template:)')
        local MODTPLT=$(echo -n "$empty"|grep -Po '(?<=#template:).*?(?=}})')
        
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

        MODOUTPUT=""
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
        TPLCONTENT="${TPLCONTENT//$empty/$MODOUTPUT}"
    done

    # INLINE BASH
    # Use to run bash inline: <!--#bash:echo Hello World!-->
    # Can be used in footer for copyright info for example
    # <!--#bash:date +"%Y"--> — All Rights Reserved
    # ---------------------------------------------------------------
    local SCRIPTS=$(grep -Po '{{\s*#bash:.*}}' "$TPLFILE")
    for empty in $SCRIPTS; do
        local COMMAND=$(echo -n "$empty"|grep -Po '(?<=#bash:).*?(?=}})')
        local OUTPUTCONTENT=$(eval $COMMAND)
        TPLCONTENT="${TPLCONTENT//$empty/$OUTPUTCONTENT}"
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

    # MARKDOWN
    # Render markdown file inline
    # Example: <!--#markdown:README.md-->
    # ---------------------------------------------------------------
    local MDS=$(echo -n "$TPLTEXT"|grep -Po '{{\s*#markdown:.*}}')
    # echo $MDS
    local empty=''
    for empty in $MDS; do
        local MDNAME=$(echo -n "$empty"|grep -Po '(?<=#markdown:).*?(?=}})')
        local MDCONTENT="$(pandoc --columns 100 ${MDNAME})"
        # Escape the & character so it doesn't get interpreted
        MDCONTENT="${MDCONTENT//&/$replacementString}"
        TPLTEXT="${TPLTEXT//$empty/$MDCONTENT}"
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
