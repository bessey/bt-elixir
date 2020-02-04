defmodule Bittorrent.Peer.Request do
  defstruct [:piece, :begin, :block_size, data: nil]
end
