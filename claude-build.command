#!/bin/zsh
cd "$HOME/Desktop/RecoverySignal2"
LOG="$HOME/Desktop/RecoverySignal2/build/claude-build.log"
FULL="$HOME/Desktop/RecoverySignal2/build/claude-build-full.log"
echo "started $(date)" > "$LOG"
xcodebuild -project RecoverySignal2.xcodeproj -scheme RecoverySignal2 -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO > "$FULL" 2>&1
echo "EXIT: $?" >> "$LOG"
grep -E "error:|warning:" "$FULL" | grep -v "DerivedData\|SwiftPM\|/build/" | sort -u >> "$LOG"
grep -c "CompileSwift\|SwiftCompile" "$FULL" >> "$LOG"
grep -E "TodayTraining|BUILD (SUCCEEDED|FAILED)" "$FULL" | tail -5 >> "$LOG"
echo "finished $(date)" >> "$LOG"
