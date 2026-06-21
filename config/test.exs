import Config

# Don't auto-start the listener/Notifier in tests (they start what they need),
# and never make a real push.
config :claude_watch, start_workers: false, delivery_backend: "log"
