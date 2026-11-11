# Developer entry points. Run `make help` for the list.

PROJECT  := Jimmy.xcodeproj
SCHEME   := Jimmy
ARCHIVES := build/archives
DERIVED  := build/DerivedData
SIM      ?= iPhone 17 Pro
# CI and local builds skip signing; archives are signed with the team in project.yml.
UNSIGNED := CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
XCB      := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) -quiet

.DEFAULT_GOAL := help
.PHONY: help bootstrap project kit build test run archive clean

help: ## List the available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-z-]+:.*## / {printf "  %-10s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

bootstrap: ## Check the toolchain, install XcodeGen if missing, generate the project
	@xcodebuild -version | head -1
	@command -v xcodegen >/dev/null || brew install xcodegen
	@$(MAKE) --no-print-directory project

project: ## Generate Jimmy.xcodeproj from project.yml
	xcodegen generate --quiet

kit: ## Run the JimmyKit package tests
	swift test --package-path Packages/JimmyKit

build: project ## Build the app for the simulator (unsigned)
	$(XCB) -destination 'generic/platform=iOS Simulator' $(UNSIGNED) build

test: project ## Run the unit tests on $(SIM) (override with SIM="...")
	$(XCB) -destination 'platform=iOS Simulator,name=$(SIM)' $(UNSIGNED) test

run: ## Build, install, launch, and screenshot Jimmy in the simulator
	./scripts/run_in_simulator.sh

archive: project ## Signed Release archive for App Store Connect, in build/archives
	xcodebuild archive -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-destination 'generic/platform=iOS' -archivePath $(ARCHIVES)/Jimmy.xcarchive -allowProvisioningUpdates

clean: ## Remove build output
	rm -rf "$(DERIVED)" Packages/JimmyKit/.build
