#!/usr/bin/env bash
# Must be bash (or compatible) for read -a and array access.

set -eu

: ${CONTAINER_REPO:="ghcr.io/scriptonbasestar"}
: ${CONTAINER_APP:=forem-ruby}

echo "CONTAINER_REPO: ${CONTAINER_REPO}"
echo "CONTAINER_APP: ${CONTAINER_APP}"


if [ "$(pwd)" != "$(git rev-parse --show-toplevel)" ]; then
	echo "This script must be run from the root of the Forem repository!" > /dev/stderr
	exit 1
fi

BUILD_PLATFORMS="${BUILD_PLATFORMS:-linux/amd64,linux/arm64}"
RUBY_VERSION="${RUBY_VERSION:-$(cat .ruby-version-next)}"
IMAGE="${CONTAINER_REPO}/${CONTAINER_APP}:${RUBY_VERSION}"

if [ -z "${SKIP_PUSH:-}" ]; then
	PUSH_FLAG="--push"
fi

IFS=',' read -ra BUILD_PLATFORMS_ARR <<< "${BUILD_PLATFORMS}"
for platform in "${BUILD_PLATFORMS_ARR[@]}"; do
  echo "Checking if image ${IMAGE} already exists for platform ${platform}..."
  if docker pull --platform "${platform}" "${IMAGE}"; then
    echo "Image ${IMAGE} already exists for platform ${platform}, but it will be overridden by this script." > /dev/stderr
  fi
done

echo "EXTERNAL_QEMU: ${EXTERNAL_QEMU:-}"
# m1?? fail??
if [ -z "${EXTERNAL_QEMU:-}" ]; then
  echo "Setting up QEMU..."
  echo docker run --rm --privileged multiarch/qemu-user-static \
		--reset \
		-p yes \
		--credential yes
	docker run --rm --privileged multiarch/qemu-user-static \
		--reset \
		-p yes \
		--credential yes
fi

if [ ! -z "${SKIP_PUSH:-}" ]; then
  echo 'build and push image'
  # shellcheck disable=SC2086
  echo docker buildx build \
    --platform "${BUILD_PLATFORMS}" \
    -f Containerfile.base \
    -t "${IMAGE}"\
    ${PUSH_FLAG:-} \
    --build-arg RUBY_VERSION="${RUBY_VERSION}" \
    .
  docker buildx build \
    --platform "${BUILD_PLATFORMS}" \
    -f Containerfile.base \
    -t "${IMAGE}"\
    ${PUSH_FLAG:-} \
    --build-arg RUBY_VERSION="${RUBY_VERSION}" \
    .
else
  echo 'build and skip push image'
  echo docker buildx build \
    -f Containerfile.base \
    -t "${IMAGE}"\
    --load \
    --build-arg RUBY_VERSION="${RUBY_VERSION}" \
    .
  # load local
  docker buildx build \
    -f Containerfile.base \
    -t "${IMAGE}"\
    --load \
    --build-arg RUBY_VERSION="${RUBY_VERSION}" \
    .
fi

