#!/usr/bin/env bash

set -e -x

echo "installing BOSH CLI"
gem install bosh_cli --no-ri --no-rdoc

echo "building CPI release..."
# export BUNDLE_GEMFILE=$PWD/bosh-src/Gemfile
# gem install bundler --no-ri --no-rdoc
# bundle install
# bundle exec bosh create release \
pushd cpi-release
bosh create release --name $CPI_RELEASE_NAME --version 0.0.0 --with-tarball
popd
mv cpi-release/dev_releases/cpi-release/$CPI_RELEASE_NAME-0.0.0.tgz cpi-release.tgz