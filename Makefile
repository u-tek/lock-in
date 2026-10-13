.PHONY: project open build test server-install server-test server-check

# Generate Lockin.xcodeproj from project.yml (needs `brew install xcodegen`). macOS only: on
# Windows, CI runs these (see .github/workflows/ios.yml).
project:
	xcodegen generate

open: project
	open Lockin.xcodeproj

# Unit tests for every module, on an iPhone simulator.
test:
	cd Packages/LKKit && xcodebuild test -scheme LKKit-Package -destination "$$(../../scripts/sim-destination.sh)"

# Build the app for the simulator without signing.
build: project
	xcodebuild build -project Lockin.xcodeproj -scheme Lockin \
		-destination "$$(scripts/sim-destination.sh)" CODE_SIGNING_ALLOWED=NO

# The API Worker in /server. Runs anywhere Node 22 does, Windows included.
server-install:
	cd server && npm ci

server-test:
	cd server && npm test

# Type-check and bundle the Worker without deploying it.
server-check:
	cd server && npm run typecheck && npm run build
