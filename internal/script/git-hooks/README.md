# git-hooks

## Option 1: Redefine the path to the repo hooks dir:

	```bash
	cd "$( git rev-parse --show-toplevel )"
	git config set --local core.hooksPath internal/script/git-hooks
	```

## Option 2: Symlink the hooks you want into the repo hooks dir:

	```bash
	cd "$( git rev-parse --show-toplevel )"
	ln -s {internal/script/git-,.git/}hooks/pre-commit
	```
