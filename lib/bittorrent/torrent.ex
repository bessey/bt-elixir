defmodule Bittorrent.Torrent do
  @moduledoc """
  A piece, as defined in the BitTorrent protocol. A torrent is made up of a fixed number of pieces of an equal fixed size.
  """

  defstruct [
    # Tracker Info
    :announce,
    # Torrent Info
    :info_sha,
    :pieces,
    :piece_size,
    :name,
    :files,
    :output_path,
    # Config
    :peer_id,
    # Live stats,
    uploaded: 0,
    downloaded: 0,
    peers: :queue.new(),
    peer_downloader_pids: []
  ]

  alias Bittorrent.{Torrent, TrackerInfo, Piece, PeerDownloader}

  def update_with_tracker_info(%Torrent{} = torrent, port) do
    info = TrackerInfo.for_torrent(torrent, port)
    %Torrent{torrent | peers: info.peers}
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  def pieces_we_need_that_peer_has(torrent, their_piece_set) do
    in_progress_pieces = Enum.map(torrent.peer_downloader_pids, &PeerDownloader.get_piece/1)

    torrent.pieces
    |> Enum.filter(fn our_piece -> Enum.at(their_piece_set, our_piece.number) end)
    |> Enum.reject(fn our_piece -> Enum.member?(in_progress_pieces, our_piece.number) end)
  end

  def update_with_piece_downloaded(torrent, piece_index, block_size) do
    pieces =
      Enum.map(torrent.pieces, fn piece ->
        if piece.number == piece_index do
          Piece.complete(piece)
        else
          piece
        end
      end)

    %Torrent{torrent | pieces: pieces, downloaded: torrent.downloaded + block_size}
  end
end
