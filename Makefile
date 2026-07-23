# Use a standard bash shell, avoid zsh or fish
SHELL:=/bin/bash

VENV_PY3M:=venv/bin/python3 -m

# Commands
PIP_COMPILE_EXEC:=${VENV_PY3M} uv pip compile --quiet --generate-hashes --strip-extras --python-platform=linux

init: sync-venv

init-venv: 
	python3.13 -m venv venv
	venv/bin/python3 -m pip install uv

sync-venv: init-venv ##@Dev Sync main venv
	venv/bin/python3 -m uv pip sync requirements/main.txt

requirements.main:
requirements.%: requirements/%.in
	$(PIP_COMPILE_EXEC) $^ --output-file requirements/$*.txt

requirements.all: requirements.dbt requirements.main
