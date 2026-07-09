SHELL:=bash

REQUIRED_BINS := sops terraform gcloud
$(foreach bin,$(REQUIRED_BINS),\
    $(if $(shell command -v $(bin) 2> /dev/null),$(info Found `$(bin)`),$(error Please install `$(bin)`)))

help:
	@echo ======= Available commands =======
	@grep '^[a-z0-9].*:' Makefile | sed 's/://g'

.DEFAULT_GOAL := help

# Adjust ENCRYPTION_KEY_PATH if your SOPS key lives elsewhere.
ENCRYPTION_KEY_PATH ?= ./encryption_key.txt

init:
	@export SECRET_KEY=$$(sops -d $(ENCRYPTION_KEY_PATH)); \
	terraform init -backend-config="encryption_key=$$SECRET_KEY"

clean:
	@rm -rf .terraform
