# Gale-splitter

### Overview

Gale-splitter is an image splitting tool for the sprite editor GraphicsGale. It consumes .gal files and produces separate clipped .png files for each layer of each frame and supports both paletted and non-paletted sprites at all colour depths.

### Usage

Either drag your files onto the executable or provide their paths from the command line.


```
USAGE:
       gale-splitter -h|--help
        displays this message

       gale-splitter -v|--version
        prints the version number

       gale-splitter --noclip
        preserves original frame size

       gale-splitter --noskip
        won't skip empty layers

EXAMPLE:
       gale-splitter file0.gal file1.gal file2.gal
```
