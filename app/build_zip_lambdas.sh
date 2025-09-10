#!/bin/bash

DIST_DIR="dist"
NODE_MODULES="$DIST_DIR/node_modules"
PACKAGE_JSON="package.json"
ZIP_DEST="../terraform"

# mkdir -p "$ZIP_DEST"

for file in $DIST_DIR/*.js; do
  base=$(basename "$file" .js)
  zipname="${ZIP_DEST}/${base}-lambda.zip"
  echo "Empaquetando $zipname..."
  zip -j "$zipname" "$file" "$PACKAGE_JSON"
  if [ -d "$NODE_MODULES" ]; then
    zip -r "$zipname" "$NODE_MODULES"
  fi
done

echo "¡Empaquetado completo!"