# Package

version     = "0.2.0"
author      = "Michael Voronin"
description = "FictionBook2 library and tools."
license     = "MIT"
srcDir      = "src"

# Deps

requires "nim > 1.6.10"

task docgen, "Generate docs":
    exec "nim doc --project --index:on --git.url:https://github.com/survivorm/fblib --outdir:htmldocs ./src/fblib.nim"

task tests, "Make tests":
    exec "testament pattern \"./tests/*.nim\""
