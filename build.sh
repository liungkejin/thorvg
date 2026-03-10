#!/usr/bin/env bash

# 构建 thorvg 项目
# Usage: ./build.sh [ohos|ios|local|android|all] [static|shared] [build-options]

FILE_NAME="$0"
LOCAL_DIR=$(cd `dirname $0`; pwd)

PLATFORM="${1}"; shift
STATIC="${1:-static}"; shift
BUILD_OPTIONS="-Ddefault_library=$STATIC -Db_lto=true -Dloaders=all -Dengines=sw,gl -Dextra=opengl_es,lottie_exp"
echo "BUILD_OPTIONS: $BUILD_OPTIONS"

USAGE="$FILE_NAME [android|ohos|ios|local] [static|shared] [build-options]"
myexit() {
  local code="$1"; shift
  echo "$@"
  exit $code
}

[[ -z "$PLATFORM" ]] && myexit 1 "$USAGE"

# 构建meson项目
# $1: platform 平台名称
# $2: arch 架构名称
# $3: cross_file 交叉编译文件
# $5: extras 额外的编译选项
meson_build() {
  local platform="$1"
  local arch="$2"
  local cross_file="$3"
  local extras="$4"

  local build_dir="$LOCAL_DIR/build/$platform/$arch"
  [[ -d "$build_dir" ]] && rm -rf "$build_dir"
  mkdir -p "$build_dir"

  local install_dir="$LOCAL_DIR/install/$platform/$arch"
  [[ -d "$install_dir" ]] && rm -rf "$install_dir"
  mkdir -p "$install_dir"

  # 默认的 Loader 只有 SVG/TTF/LOTTIE/，如果需要修改，可以添加选项 -Dloaders="lottie, png, jpg"
  local cross_params=""
  [[ -z "$cross_file" ]] || cross_params="--cross-file=$cross_file"
  meson setup $BUILD_OPTIONS $extras --prefix="$install_dir" $cross_params $build_dir
  ninja -C $build_dir install

  [[ $? -eq 0 ]] && echo ">>>> build [$platform-$arch] finish！install dir: $install_dir"
}

## Build for Android
## 默认使用环境变量 ANDROID_HOME / ANDROID_SDK_ROOT
## 默认使用ndk version 为: 27.3.13750724
## 默认使用api level 为: 24
build_for_android() {
  local ndk_version="27.3.13750724"
  local sdk=${ANDROID_HOME:-${ANDROID_SDK_ROOT}}
  local ndk=${sdk}/ndk/$ndk_version
  local api=24
  if [[ -z "$sdk" ]] || [[ ! -d "$sdk" ]]; then
    myexit 1 "env variable ANDROID_HOME or ANDROID_SDK_ROOT is not set or not a directory"
  fi
  if [[ -z "$ndk" ]] || [[ ! -d "$ndk" ]]; then
    myexit 1 "NDK version $ndk_version is not set or not a directory"
  fi
  # host_tag 直接去 toolchains/llvm/prebuilt/ 文件夹下的第一个文件夹名
  local host_tag=$(ls $ndk/toolchains/llvm/prebuilt/ | head -n 1)

  local cross_file="/tmp/.thorvg_android_cross_aarch64.txt"
  sed -e "s|NDK|$ndk|g" -e "s|HOST_TAG|$host_tag|g" -e "s|API|$api|g" $LOCAL_DIR/cross/android_aarch64.txt > $cross_file
  meson_build android arm64-v8a "$cross_file" $@

  cross_file="/tmp/.thorvg_android_cross_armv7a.txt"
  sed -e "s|NDK|$ndk|g" -e "s|HOST_TAG|$host_tag|g" -e "s|API|$api|g" $LOCAL_DIR/cross/android_armv7a.txt > $cross_file
  meson_build android armeabi-v7a "$cross_file" $@
}

## Build for OpenHarmony
## 默认使用环境变量 OHOS_SDK
## 默认使用api level 为: 21
build_for_ohos() {
  local sdk=${OHOS_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony}
  if [[ -z "$sdk" ]] || [[ ! -d "$sdk" ]]; then
    myexit 1 "env variable OHOS_SDK is not set and $sdk not exists!"
  fi

  local cross_file="/tmp/.thorvg_ohos_cross.txt"
  sed -e "s|OHOS_SDK|$sdk|g" $LOCAL_DIR/cross/ohos_aarch64.txt > $cross_file

  export PATH=$sdk/native/build-tools/cmake/bin/:$PATH
  meson_build harmony arm64-v8a "$cross_file" $@ "-Dthreads=false"
}

build_for_ios() {
  meson_build ios arm64-v8a "$LOCAL_DIR/cross/ios_arm64.txt" $@
}

build_for_local() {
  meson_build local host "" $@
}

build() {
  case $PLATFORM in
    android)
      build_for_android $@ ;;
    ohos)
      build_for_ohos $@;;
    ios)
      build_for_ios $@;;
    local)
      build_for_local $@;;
    all)
      build_for_android $@
      build_for_ohos $@
      build_for_ios $@
      build_for_local $@
      ;;
    *)
      myexit 1 "$USAGE" ;;
  esac
}

build $@