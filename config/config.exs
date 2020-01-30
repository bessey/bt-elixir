import Config

config :logger, :console,
  format: "$time [$level] $levelpad$message [ $metadata]\n",
  metadata: [
    # :info_sha,
    :peer
  ],
  level: :debug

config :tesla, adapter: Tesla.Adapter.Hackney
