#!/bin/bash
bundle install
rake
if [ "Linux" = `uname` ]; then
  rake bench
fi
