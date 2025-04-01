ifeq ($(OS),Windows_NT)
	BUILD_SCRIPT := build.bat
else
	BUILD_SCRIPT := ./build.sh
endif

.PHONY: build
build:
	$(BUILD_SCRIPT)