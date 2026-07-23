#!/bin/bash

BAL_EXAMPLES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BAL_CENTRAL_DIR="$HOME/.ballerina/repositories/central.ballerina.io"
BAL_HOME_DIR="$BAL_EXAMPLES_DIR/../ballerina"

set -e

case "$1" in
build)
  BAL_CMD="build"
  ;;
run)
  BAL_CMD="run"
  ;;
*)
  echo "Invalid command provided: '$1'. Please provide 'build' or 'run' as the command."
  exit 1
  ;;
esac

# Read the Ballerina package name
BAL_PACKAGE_NAME=$(awk -F'"' '/^name/ {print $2}' "$BAL_HOME_DIR/Ballerina.toml")

# Push the package to the local repository
cd "$BAL_HOME_DIR" &&
  bal pack &&
  bal push --repository=local

# Remove the cache directories in the repositories
cacheDirs=$(ls -d "$BAL_CENTRAL_DIR"/cache-* 2>/dev/null) || true
for dir in "${cacheDirs[@]}"; do
  [ -d "$dir" ] && rm -r "$dir"
done
echo "Successfully cleaned the cache directories"

# Create the package directory in the central repository; it is absent when no modules were pulled
mkdir -p "$BAL_CENTRAL_DIR/bala/ballerinax/$BAL_PACKAGE_NAME"

# Update the central repository from the local one
BAL_DESTINATION_DIR="$BAL_CENTRAL_DIR/bala/ballerinax/$BAL_PACKAGE_NAME"
BAL_SOURCE_DIR="$HOME/.ballerina/repositories/local/bala/ballerinax/$BAL_PACKAGE_NAME"
[ -d "$BAL_DESTINATION_DIR" ] && rm -r "$BAL_DESTINATION_DIR"
[ -d "$BAL_SOURCE_DIR" ] && cp -r "$BAL_SOURCE_DIR" "$BAL_DESTINATION_DIR"
echo "Successfully updated the local central repositories"

# Build or run every example project
for dir in "$BAL_EXAMPLES_DIR"/*/; do
  if [ -f "$dir/Ballerina.toml" ]; then
    (cd "$dir" && bal "$BAL_CMD" --offline)
  fi
done

# Remove generated JAR files
find "$BAL_HOME_DIR" -maxdepth 2 -type f -name "*.jar" | while read -r JAR_FILE; do
  rm "$JAR_FILE"
done
