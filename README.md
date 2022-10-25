# README.md

Smash.sh is a stand-alone Bash script aimed at generating full-featured, routable static websites from reusable HTML snippets. It features the most basic templating engine ever possible but allows to organize your content in a SEO-friendly way. All Statix-based websites contain these parts:

| Feature                                                       | How?                                      |
| :------------------------------------------------------------ | :---------------------------------------- |
| Reuse HTML snippets anywhere in your HTML code                | `{{#include:path/to/snippet.html}}`       |
| Generate HTML from a CSV file and an HTML snippet             | `{{#data:mywork.csv#template:card.html}}` |
| define page specific variables                                | `{{#set:title=Hi there 👋}}`             |
| use defined variables anywhere you want                       | `{{title}}`                               |
| render markdown anywhere (You will need `pandoc` installed.)  | `{{#markdown:README.md}}`                 |
| Define site-wide variables like `base-name`, `base-url`, etc. | Edit the file `_data.conf`                |
| Define routes, like about.html -> /about/.                    | Edit the file `_routes.conf`              |
| TODO:Generate sitemap.xml                                     | Automatic                                 |

This script is **heavily** based off [Statix](https://gist.github.com/plugnburn/c2f7cc3807e8934b179e)

---

# Data files and folders

- __routes.conf__: a file that maps each publicly accessible template to a SEO-friendly URL
- __data.conf__: a file that contains global data for your website (base url, author, support email, etc)
- __source/__: a folder containind all the template files that will be processed.
- __source/static__: a folder for assets that are copied over without processing.
- __output/__: a directory with optional files copied to the output website directory with no processing.

This script is also lightweight. Aside from some standard file management commands such as `cp`, `mkdir` and `rm`, the only serious dependency for Statix is GNU Grep compiled with PCRE support (i.e. the version that supports `-P` flag, included in most Linux distributions).

This script is based off [Statix - the simplest static website generator in Bash](https://gist.github.com/plugnburn/c2f7cc3807e8934b179e)

## Templates

In Statix, a template is a simple HTML file (or its partial) where also several special directives are allowed:

- __Include block__ (`{{#include:_include/_footer.html}}`) is a block that allows including another template to reuse existing HTML code.
- __Set block__ (`{{#set:variable=some new value}}`) is a block that allows setting a variable to the specific string value.
- __Use block__ (`{{variable}}`) is a block that inserts a previously set variable value.

Note that if a variable is set twice, the first set block occurence overrides any others. So if you want to set some page-specific variables and want to be sure they will not be overwritten by any included templates, please put the appropriate set blocks at the very top of the page.

## Variables

## Inline bash

## Markdown support

## Route configuration

To let Statix know the entire structure of your website, it's mandatory to specify all routing in a separate file (say, `routes.conf`). This file contains the mapping of a physical template name (relative to your templates directory) and logical URL (relative to the supposed website root). Note that in order to avoid any building errors all URLs **must** end in `/` (forward slash). Physical names and URLs are separated with a colon (`:`). Each mapping pair is on a new line.

Example of a typical `routes.conf` file:

```
index.html:/
about.html:/about-us/
contact.html:/contact/
work.html:/portfolio/
```

## Build process

Building the website out of the source materials (templates, routes and assets) is as simple as calling the script with all necessary parameters:

`/path/to/smash.sh`

Everything but asset directory is mandatory here. If `<asset directory>` is not specified, output will contain just the generated HTML tree and nothing else will be copied. If `<output directory>` doesn't exist, it will be created, **but if it does and is not empty, it will be completely overwritten, so be careful!** After the build completes, you can transfer the output directory contents wherever you want to host it.

