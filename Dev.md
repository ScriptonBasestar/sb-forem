# Dev

## Build image

1. Allow personal token from organization(if you fork)
2. change docker image org/repo/tag name
3. build image and push

```bash
export CONTAINER_REPO="ghcr.io/your_org/your_repo""

# mac m1
#export DOCKER_BUILDKIT=1
#export DOCKER_CLI_EXPERIMENTAL=enabled
#export BUILD_PLATFORMS="linux/arm64"
#export RUBY_VERSION="${RUBY_VERSION:-$(cat .ruby-version-next)}"
#export PUSH_FLAG="--push"
#export IMAGE="test1"
export SKIP_PUSH="true"

scripts/build_base_ruby.sh
scripts/build_containers.sh
```

## Local Run

1. install dip

- gem install dip
- rbenv rehash

2. cp .env.sample .env
3. scripts/build_base_ruby_m1_local.sh
4. scripts/build_containers_m1_local.sh
5. dip bundle
6. dip pnpm i
7. `dip rake db:create db:migrate db:seed`
8. `dip up`
