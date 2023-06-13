test/bats/bin/bats:
		git submodule init
		git submodule update

tests: test/bats/bin/bats
		./test/bats/bin/bats --print-output-on-failure -r test/units/