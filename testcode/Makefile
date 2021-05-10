# Build the code we use for some tests

BIN_SFILES = $(filter-out s/_%,$(wildcard s/*))
MODULE_SFILES = $(wildcard module/s/*)
UTIL_SFILES = $(wildcard utility/s/*)

all: \
	dirs \
	${BIN_SFILES:s/%=bin/%,ffc} \
	${MODULE_SFILES:module/s/%=module/bin/%,ffa} \
	${UTIL_SFILES:utility/s/%=utility/bin/%,ffc}

bin/%,ffc: s/%
	rm -f bin/$*,* && riscos-objasm -apcs 3/32 -o o/$* $? && riscos-link -bin -o $@ o/$* && mv bin/$*,ffd $@

module/bin/%,ffa: module/s/%
	riscos-objasm -apcs 3/32 -o module/o/$* $? && riscos-link -bin -o $@ module/o/$* && mv module/bin/$*,ffd $@

utility/bin/%,ffc: utility/s/%
	riscos-objasm -apcs 3/32 -o utility/o/$* $? && riscos-link -bin -o $@ utility/o/$* && mv utility/bin/$*,ffd $@

dirs:
	@mkdir -p o
	@mkdir -p module/o
	@mkdir -p utility/o
