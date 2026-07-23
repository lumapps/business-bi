# Use a standard bash shell, avoid zsh or fish
SHELL:=/bin/bash

VENV_PY3M:=venv/bin/python3 -m

# Commands
PIP_COMPILE_EXEC:=${VENV_PY3M} uv pip compile --quiet --generate-hashes --strip-extras --python-platform=linux

init-dbt: sync-venv
init-meltano: sync-venv-meltano

init-venv: 
	python3.13 -m venv venv
	venv/bin/python3 -m pip install uv

sync-venv: init-venv ##@Dev Sync main venv
	venv/bin/python3 -m uv pip sync requirements/main.txt

init-venv-meltano:
	python3.13 -m venv venv-meltano
	venv-meltano/bin/python3 -m pip install uv

sync-venv-meltano: init-venv-meltano ##@Dev Sync meltano venv (optional, requires Python 3.10)
	venv-meltano/bin/python3 -m uv pip sync requirements/meltano.txt

requirements.main:
requirements.%: requirements/%.in
	$(PIP_COMPILE_EXEC) $^ --output-file requirements/$*.txt

requirements.all: requirements.dbt requirements.main requirements.meltano
