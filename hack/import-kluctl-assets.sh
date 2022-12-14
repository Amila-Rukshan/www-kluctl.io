#!/bin/bash

set -e

FLUX_KLUCTL_CONTROLLER_DIR="content/en/docs/flux"
KLUCTL_DIR="content/en/docs/reference/commands"

if [ ! "$(command -v jq)" ]; then
  echo "Please install 'jq'."
  exit 1
fi

fatal() {
    echo '[ERROR] ' "$@" >&2
    exit 1
}

# Set os, fatal if operating system not supported
setup_verify_os() {
    if [ -z "${OS}" ]; then
        OS=$(uname)
    fi
    case ${OS} in
        Darwin)
            OS=darwin
            ;;
        Linux)
            OS=linux
            ;;
        *)
            fatal "Unsupported operating system ${OS}"
    esac
}

# Set arch, fatal if architecture not supported
setup_verify_arch() {
    if [ -z "${ARCH}" ]; then
        ARCH=$(uname -m)
    fi
    case ${ARCH} in
        arm|armv6l|armv7l)
            ARCH=arm
            ;;
        arm64|aarch64|armv8l)
            ARCH=arm64
            ;;
        amd64)
            ARCH=amd64
            ;;
        x86_64)
            ARCH=amd64
            ;;
        *)
            fatal "Unsupported architecture ${ARCH}"
    esac
}


controller_version() {
  curl -u kluctlbot:$GITHUB_TOKEN -f -s "https://api.github.com/repos/kluctl/$1/releases" | jq -r '.[] | .tag_name' | sort -V | tail -n 1
}

download_doc() {
  URL="$1"
  DEST="$2"
  HUGETABLE="$3"

  TMP="$(mktemp)"
  curl -f -# -Lf "$URL" > "$TMP"

  # Ok, so this section is not pretty, but we have a number of issues we need to look at here:
  #
  # 1. Some lines start with editor instructions (<!-- line length, blah something .. -->)
  # 2. Some title lines go <h1>Title is here</h1>
  # 3. While others go     # Here is the title you're looking for...
  #

  FIRST_LINE="$(grep -vE "^<!--" "$TMP" | head -n1)"
  if echo "$FIRST_LINE" | grep -q "<h1>" ; then
    TITLE="$(echo "$FIRST_LINE" | cut -d'<' -f2 | cut -d'>' -f2 | sed 's/^\#\ //')"
  elif echo "$FIRST_LINE" | grep -E "^# "; then
    TITLE="$(echo "$FIRST_LINE" | sed 's/^\#\ //')"
  else
    echo "Don't know what to do with '$FIRST_LINE' in $TMP."
    exit 1
  fi

  if [ -n "$TITLE" ]; then
    {
      echo "---"
      echo "title: $TITLE"
      echo "description: Flux Kluctl Controller documentation."
      echo "importedDoc: true"
      if [ -n "$HUGETABLE" ]; then
        echo "hugeTable: true"
      fi
      echo "---"
    } >> "$DEST"
    grep -vE "^<!--" "$TMP" |sed '1d' >> "$DEST"
    rm "$TMP"
  else
    mv "$TMP" "$DEST"
  fi
}

{
  # flux-kluctl-controller CRDs
  KLUCTL_CONTROLLER_VER="$(controller_version flux-kluctl-controller)"
  echo KLUCTL_CONTROLLER_VER=$KLUCTL_CONTROLLER_VER
  download_doc "https://raw.githubusercontent.com/kluctl/flux-kluctl-controller/$KLUCTL_CONTROLLER_VER/docs/api/kluctldeployment.md" "$FLUX_KLUCTL_CONTROLLER_DIR/api.md"
  download_doc "https://raw.githubusercontent.com/kluctl/flux-kluctl-controller/$KLUCTL_CONTROLLER_VER/README.md" "$FLUX_KLUCTL_CONTROLLER_DIR/controller.md"
  download_doc "https://raw.githubusercontent.com/kluctl/flux-kluctl-controller/$KLUCTL_CONTROLLER_VER/docs/spec/v1alpha1/kluctldeployment.md" "$FLUX_KLUCTL_CONTROLLER_DIR/kluctldeployment.md" "HUGETABLE"
  download_doc "https://raw.githubusercontent.com/kluctl/flux-kluctl-controller/$KLUCTL_CONTROLLER_VER/docs/install.md" "$FLUX_KLUCTL_CONTROLLER_DIR/install.md"
}

sync_docs() {
  REPO="$1"
  SOURCE="$2"
  DEST="$3"
  WITH_ROOT_README="$4"

  TMP="$(mktemp -d)"
  TMP_LATEST="$TMP/latest.json"

  VERSION=$(curl -u kluctlbot:$GITHUB_TOKEN -f -s "https://api.github.com/repos/$REPO/tags" | jq -r '.[] | .name' | sort -V | tail -n 1)
  echo VERSION=$VERSION

  git clone https://github.com/$REPO.git $TMP/repo
  (
    set -e

    cd $TMP/repo
    git checkout $VERSION

    if [ "$WITH_ROOT_README" = "true" ]; then
      cat README.md | sed "s|./$SOURCE/|./|g" > $SOURCE/README.md
    fi

    cd $SOURCE

    # rename all README.md files to _index.md
    for x in $(find . -name README.md); do
      mv $x $(dirname $x)/_index.md
    done
  )

  go run ./convert-md-to-hugo --docs-dir $TMP/repo/$SOURCE --github-repo https://github.com/$REPO
  cp -rv $TMP/repo/docs/* $DEST/

  rm -rf "$TMP"
}

{
    setup_verify_os
    setup_verify_arch

    sync_docs kluctl/kluctl docs content/en/docs/kluctl false
    sync_docs kluctl/template-controller docs content/en/docs/template-controller true
}

{
  # provide Kluctl install script
  if [ ! -d static ]; then
    mkdir static
  fi
  curl -f -s -# -Lf https://raw.githubusercontent.com/kluctl/kluctl/main/install/kluctl.sh -o static/install.sh
}
