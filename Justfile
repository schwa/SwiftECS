default:
	just --list

preview-docs:
	swift package --disable-sandbox preview-documentation --target SwiftECS

check-docs:
	swift package --allow-writing-to-directory /tmp/SwiftECS-docs generate-documentation --target SwiftECS --warnings-as-errors --output-path /tmp/SwiftECS-docs
