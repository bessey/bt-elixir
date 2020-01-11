defmodule Bittorrent.Peer do
  defstruct [:name, :reserved, :info_hash, :id, :pieces]
end
