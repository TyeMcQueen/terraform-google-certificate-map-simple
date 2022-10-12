SHELL := bash
.SHELLFLAGS := -eu -o pipefail -c
# Mac's gnu Make 3.81 does not support .ONESHELL:
# .ONESHELL:
.DELETE_ON_ERROR:
MAKEFLAGS += --warn-undefined-variables
MAKEFLAGS += --no-builtin-rules

## Update list of input variables in README.md
README.md.new: variables.tf README.md
	@( sed -n '1,/^## Input Variables/p' README.md; \
	  echo; grep -n '^variable ' < variables.tf \
		| sed -e 's/:variable  *"/:/' -e 's/".*//' -e \
		's!^\(.*\):\(.*\)!* [\2](/variables.tf#L\1)!' | sort \
	) > README.md.new
	@if  ! diff -q README.md README.md.new >/dev/null;  then \
		echo "Updating list of input variables in README.md..."; \
		run-cmd cp README.md.new README.md; \
		run-cmd touch README.md.new; \
	else \
		echo "(List of input variables in README.md already up-to-date.)"; \
	fi
