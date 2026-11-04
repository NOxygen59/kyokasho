#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 NOxygen59
#
# Version Mac (#55) : construit le moteur `llama-server` (llama.cpp, MIT) embarqué dans l'app pour OvisOCR2.
# Version épinglée, processeur seul, instructions AVX2 présentes sur le Mac Intel visé (i5-8257U probable, à confirmer).
# Le binaire reste hors du dépôt. Usage : tools/build_llama_server_mac.sh <dossier de travail>
set -euo pipefail
WORK=$1
TAG=v0.8.0
mkdir -p "$WORK"
[[ -d "$WORK/llama.cpp" ]] || git clone --depth 1 --branch "$TAG" https://github.com/ggml-org/llama.cpp "$WORK/llama.cpp"
cmake -S "$WORK/llama.cpp" -B "$WORK/build-x86_64" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 \
  -DBUILD_SHARED_LIBS=OFF -DGGML_METAL=OFF -DGGML_NATIVE=OFF -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_SERVER=ON -DLLAMA_BUILD_TOOLS=ON -DLLAMA_CURL=OFF -DLLAMA_BUILD_UI=OFF -DLLAMA_OPENSSL=OFF
cmake --build "$WORK/build-x86_64" --target llama-server -j 6
lipo -archs "$WORK/build-x86_64/bin/llama-server"
otool -L "$WORK/build-x86_64/bin/llama-server"
