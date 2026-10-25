"""Compile the production chat value types without the iOS UI or network client."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
food = (root / 'RecoverySignal2/Food/FoodModels.swift').read_text()
food = food[food.index('nonisolated struct FoodItem'):food.index('@Model')]
chat = (root / 'RecoverySignal2/Food/FoodChatModel.swift').read_text()
chat = chat[chat.index('nonisolated struct FoodChatMessage'):chat.index('@Observable')]
dates = (root / 'RecoverySignal2/Food/FoodLogDate.swift').read_text()
dates = dates[dates.index('nonisolated enum FoodLogDate'):]
# Only the UI's number formatter is stubbed; validation/date/scaling/encoding use production code.
formatter = 'enum DetailFormat { static func safeInt(_ n: Double) -> Int { n.isFinite ? Int(max(-999999999, min(999999999,n))) : 0 } }'
with tempfile.TemporaryDirectory(prefix='trace-chat-checks-') as tmp:
    source = Path(tmp) / 'Logic.swift'
    source.write_text('import Foundation\n' + formatter + '\n' + food + chat + dates)
    binary = str(Path(tmp) / 'checks')
    subprocess.run(['swiftc', '-module-cache-path', '/tmp/trace-swift-module-cache', str(source), str(root / 'DiagnosticsTests/check_food_chat.swift'), '-o', binary], check=True)
    subprocess.run([binary], check=True)
