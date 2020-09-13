FROM ruby:2.7.1-buster

COPY . /dns-server

WORKDIR /dns-server

RUN bundle install

