#!/bin/sh

ORG="spring-projects"
curl https://api.github.com/orgs/${ORG}/repos?per_page=1000

