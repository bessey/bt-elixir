defmodule Bittorrent.Peer do
  defmodule State do
    defstruct [
      # About them
      :name,
      :reserved,
      :info_hash,
      :id,
      :pieces,
      :ip,
      :port,
      socket: nil,
      # Their feelings for us
      choked: true,
      interested: false,
      # Our feelings for them
      interested_in: false,
      choking: true,
      # Stats
      requests_in_flight: 0
    ]

    def have_piece(peer, piece) do
      pieces = List.replace_at(peer.pieces, piece, true)
      %Bittorrent.Peer.State{peer | pieces: pieces}
    end
  end
end
