defmodule Bittorrent.Peer do
  defstruct [:name, :reserved, :info_hash, :peer_id, :pieces]

  def pieces(torrent_info, bitfield) do
  end
end
