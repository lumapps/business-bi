# Use a standard bash shell, avoid zsh or fish
SHELL:=/bin/bash

init: sync-venv

init-venv: 
	python3.13 -m venv venv
	venv/bin/python3 -m pip install uv
