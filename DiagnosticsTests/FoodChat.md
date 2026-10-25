# Food chat and dictation

Describe now opens a locally persisted daily conversation. The history date chooses a conversation; each proposed food has its own explicit logging date and meal. Relative date words refer to the actual current date in the user's timezone, even when an old conversation is open.

The AI returns structured proposals. Dates, slots, finite nonnegative nutrients and portion bounds are validated before cards appear. Suggestions remain estimates (no verified badge). A newer assistant response supersedes older unconfirmed cards. Tap the card to change grams, date or meal, then tap + to confirm. Saving uses the existing FoodLogger/Health sync path. Stable FoodItem IDs are persisted in chat history and compared against FoodEntry records, preventing repeated taps/reopening from relogging confirmed cards. Editing/deleting already saved food remains in the food diary.

Chat history is a protected atomic JSON file in Application Support, excluded from cloud backup. Raw audio is not stored by Trace. Up to the last 16 conversation messages plus proposal status are sent through the existing AIClient when Send is tapped (respecting the existing local/Gemini settings). No background recording; dictation stops on leaving the screen or backgrounding.

Speech uses SFSpeechRecognizer with en-GB, pl-PL or de-DE. On-device recognition is required when the recognizer reports support; otherwise an explicit online-dictation confirmation precedes permission requests. Availability must be checked on the actual phone. Apple documents that not all recognizers can work offline: https://developer.apple.com/documentation/speech/sfspeechrecognizer/supportsondevicerecognition . Audio never goes to Gemini through this feature; the editable transcript goes through the normal text AI request only after Send.

## Verification

Run `python3 DiagnosticsTests/run_food_chat_checks.py` for production value-type checks: portion scaling, rejected malformed dates/amounts/macros/meal slots, Unicode and stable IDs across JSON persistence. These do not test the AI's natural-language interpretation or microphone hardware.

On an iPhone:
1. Food → choose meal → Describe. Type “Jutro na śniadanie dwa jajka” or “Für morgen zum Frühstück zwei Eier”. Check the full date and meal printed on each proposal.
2. Tap a food and change grams. Save changes: no food should be logged yet. Tap +: one entry should appear in the specified day's diary/Health.
3. Close/reopen the chat: the confirmed food should show a checkmark. Check both dates' totals and verify no duplicate entry.
4. Before confirming another proposal, say “Actually three eggs”. Only the newest unconfirmed proposal should remain addable. Already saved foods must not be silently edited.
5. Use the chat-date picker to revisit another day's conversation. “Tomorrow” still means tomorrow relative to now.
6. Dictate separately using English, Polski and Deutsch. Stop, edit the transcript, then Send. Deny microphone/speech permissions and verify typing remains available. Background the app during recording and check that recording stops.
7. With AI unavailable, verify the error is visible, the typed message is retained for retry, and no food is saved.

## Background replies

FoodChatStore is shared and owns one in-flight Task per chat day. Closing Describe no longer cancels a request; returning attaches to the same pending state, and the reply is written to local history. A failed/interrupted request offers Retry. On a fresh process, a chat ending in a user message is treated as unfinished; there is no automatic resend (avoids unrequested duplicate API calls).

All Gemini calls through AIClient request finite UIApplication background time, including model discovery and retries. Completion/failure releases the allowance; expiration cancels the work and releases it. This is best-effort completion while switching apps/locking, not an unlimited background worker. Force-quitting or system termination can interrupt it. See https://developer.apple.com/documentation/uikit/extending-your-app-s-background-execution-time . The microphone still stops on backgrounding. Other AI screens receive the shared Gemini execution allowance, but this change only adds persistent screen-independent result ownership to food chat.

The production lifetime helper is exercised by check_ai_background.swift with a UIKit stand-in: success, failure, expiry, caller cancellation and exactly-once cleanup. Real-device check: send a food description, switch apps immediately, return and verify a single reply. Also close/reopen Describe while pending, and force-quit once to verify Retry rather than a stuck spinner. No food should log without +.

Gemini network timeouts receive one attempt on an untried fallback model, skipping repeated model discovery. A second timeout stops with a specific error. Cancellation/background expiry is not retried. Retries only generate proposals; they never log food. Live network timing remains dependent on the connection and provider.
