defmodule Bittorrent.Peer do
  defmodule State do
    defstruct [
      :name,
      :reserved,
      :info_hash,
      :id,
      :pieces,
      socket: nil,
      # Their feelings for us
      choked: true,
      interested: false,
      # Our feelings for them
      interested_in: false,
      choking: true
    ]

    def have_piece(peer, piece) do
      pieces = List.replace_at(peer.pieces, piece, true)
      %Bittorrent.Peer.State{peer | pieces: pieces}
    end
  end
end
