import Config

config :logger, :default_handler, level: :debug

config :logger,
  level: :debug

config :llm_db,
  compile_embed: false,
  integrity_policy: :warn

# Enable RPC server in dev mode for CLI stdio communication
config :opal,
  start_rpc: true
