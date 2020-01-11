defmodule Bittorrent.Peer do
  defstruct [
    :name,
    :reserved,
    :info_hash,
    :id,
    :pieces,
    # Their feelings for us
    choked: true,
    interested: false,
    # Our feelings for them
    interested_in: false,
    choking: true
  ]

  def have_piece(peer, piece) do
    pieces = List.replace_at(peer.pieces, piece, true)
    %Bittorrent.Peer{peer | pieces: pieces}
  end
end
