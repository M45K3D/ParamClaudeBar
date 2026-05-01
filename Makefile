.PHONY: build app zip dmg release-artifacts verify-release install clean

build:
	cd macos && swift build -c release

app:
	bash macos/scripts/build.sh

zip:
	bash macos/scripts/build.sh --zip
	bash macos/scripts/verify-release.sh macos/ParamClaudeBar.zip

dmg:
	bash macos/scripts/build.sh --dmg
	bash macos/scripts/verify-release.sh macos/ParamClaudeBar.dmg

release-artifacts:
	bash macos/scripts/build.sh --zip --dmg
	bash macos/scripts/verify-release.sh macos/ParamClaudeBar.zip
	bash macos/scripts/verify-release.sh macos/ParamClaudeBar.dmg

verify-release:
	bash macos/scripts/verify-release.sh macos/ParamClaudeBar.zip
	if [ -f macos/ParamClaudeBar.dmg ]; then bash macos/scripts/verify-release.sh macos/ParamClaudeBar.dmg; fi

install: app
	rm -rf /Applications/ParamClaudeBar.app
	cp -R macos/ParamClaudeBar.app /Applications/

clean:
	cd macos && swift package clean
	rm -rf macos/ParamClaudeBar.app macos/ParamClaudeBar.zip macos/ParamClaudeBar.dmg
