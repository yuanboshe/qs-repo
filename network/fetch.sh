#!/bin/bash
# @qs template

# @description Fixture: network metadata and download argument review.
# @step Resolve a download URL without performing network IO.
# @step Print the expected checksum for pre-run review.
# @platform linux/ubuntu>=22.04 linux/debian>=12
# @shell bash
# @requires curl sha256sum
# @effects network-download file-write
# @network raw.githubusercontent.com downloads.fixture.invalid

# @arg URL that would be downloaded by a real asset.
DOWNLOAD_URL="https://downloads.fixture.invalid/archive.tgz"

# @arg Expected SHA256 checksum for the download.
CHECKSUM="{{.checksum}}"

main() {
  echo "download_url=${DOWNLOAD_URL}"
  echo "checksum=${CHECKSUM}"
}

main
