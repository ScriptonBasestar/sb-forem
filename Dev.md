# Dev

## Build image

1. Allow personal token from organization(if you fork)
2. change docker image org/repo/tag name
3. build image and push

```bash
ghcr.io/scriptonbasestar/forem-ruby:{RUBY_VERSION}

allow personal token from organization

scripts/build_base_ruby_image.sh
scripts/build_containers.sh
```

## Local Run

1. install dip
  - gem install dip
  - mac fail
2. cp .env.sample .env
3. run `dip up`

## Local Dev

gem install bundler
bundle install
yarn

docker-compose up -f docker-compose.dev.yml
honcho start -f Procfile.dev
