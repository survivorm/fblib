# Package

version     = "0.1.0"
author      = "Michael Voronin"
description = "FictionBook2 library and tools."
license     = "MIT"
srcDir      = "src"

# Deps

requires "nim >= 1.6.10"

task docgen, "Generate docs":
    exec "nim doc ./src/fblib.nim"

task tests, "Make tests":
    exec "testament pattern \"./tests/*.nim\""
