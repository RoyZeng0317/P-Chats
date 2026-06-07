PROJECT := p-chats-26652

.PHONY: setup run rules build-android build-windows build-linux clean

setup:                          ## Full first-time setup (pub get + Firestore rules)
	flutter pub get
	firebase deploy --only firestore:rules --project $(PROJECT)

run:                            ## Run in debug mode (pick device interactively)
	flutter run

rules:                          ## Deploy Firestore security rules only
	firebase deploy --only firestore:rules --project $(PROJECT)

build-android:                  ## Build release APK
	flutter build apk --release
	@echo "APK → build/app/outputs/flutter-apk/app-release.apk"

build-windows:                  ## Build Windows release EXE
	flutter build windows --release
	@echo "EXE → build/windows/x64/runner/Release/"

build-linux:                    ## Build Linux release binary
	flutter build linux --release
	@echo "Binary → build/linux/x64/release/bundle/"

clean:                          ## Remove build artifacts
	flutter clean

help:                           ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?##' $(MAKEFILE_LIST) | \
	  awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'
