defmodule Bittorrent.Peer do
  defstruct [:name, :reserved, :info_hash, :peer_id, :pieces]
end
