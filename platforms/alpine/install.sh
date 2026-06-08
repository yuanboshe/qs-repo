#!/bin/sh

# @description Fixture: platform-specific sh template for inspect filters.
# @step Show a package selected through directory config.
# @platform linux/alpine>=3.19
# @shell sh
# @requires apk
# @effects package-install
# @network dl-cdn.alpinelinux.org

# @arg Alpine package name.
PACKAGE="{{.package}}"

main() {
  echo "package=${PACKAGE}"
}

main
