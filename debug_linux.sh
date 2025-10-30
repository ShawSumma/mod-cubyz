#!/bin/bash

cd "$(dirname "$0")"

fail () {
	exit 1
}

if ! ./scripts/install_compiler_linux.sh
then
	echo Failed to install Zig compiler.
	fail
fi

echo "Building Zig Cubyz ($@) from source. This may take a few minutes..."

./compiler/zig/zig build --prominent-compile-errors "$@"

if [ $? != 0 ]
then
	fail
fi

echo "Cubyz successfully built!"
echo "Launching Cubyz."

set -e

for i in mods/web49/*.c; do
	zig cc --target=wasm32-wasi $i -o ${i%.c}.wasm -nostdlib -nostdinc -Wl,--no-entry -O3	
done

./zig-out/bin/Cubyz


