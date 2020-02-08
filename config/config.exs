# This file is responsible for configuring your umbrella
# and **all applications** and their dependencies with the
# help of Mix.Config.
#
# Note that all applications in your umbrella share the
# same configuration and dependencies, which is why they
# all use the same configuration file. If you want different
# configurations or dependencies per app, it is best to
# move said applications out of the umbrella.
use Mix.Config

config :bittorrent_web,
  generators: [context_app: :bittorrent]

# Configures the endpoint
config :bittorrent_web, BittorrentWeb.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "jNPg5GMRLxZAK+WAOw7EBlrYhzRpz15H6R4v7tHCz749LLMOBLjGQ7U39N0vnGHe",
  render_errors: [view: BittorrentWeb.ErrorView, accepts: ~w(html json)],
  pubsub: [name: BittorrentWeb.PubSub, adapter: Phoenix.PubSub.PG2],
  live_view: [
    # TODO this needs DRYing up
    signing_salt: "FW6+oVsv"
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id, :peer]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env()}.exs"

config :tesla, adapter: Tesla.Adapter.Hackney
