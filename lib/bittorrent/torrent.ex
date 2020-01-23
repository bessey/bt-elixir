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
    peers: [],
    peer_downloader_pids: [],
    assigned_peers: []
  ]

  alias Bittorrent.{Torrent, TrackerInfo, Piece}

  def update_with_tracker_info(%Torrent{} = torrent, port) do
    info = TrackerInfo.for_torrent(torrent, port)
    %Torrent{torrent | peers: info.peers}
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  def blocks_we_need_that_peer_has(our_pieces, their_piece_set) do
    our_pieces
    |> Enum.filter(fn our_piece -> Enum.at(their_piece_set, our_piece.number) end)
    |> Enum.flat_map(fn our_piece_they_have -> blocks_we_need_in_piece(our_piece_they_have) end)
  end

  defp blocks_we_need_in_piece(piece) do
    Piece.missing_blocks(piece)
    |> Enum.map(fn block_index -> {piece.number, block_index} end)
  end

  def request_for_block(torrent, piece_index, block_index) do
    block_size = Piece.block_size()
    full_size = size(torrent)
    begin = block_index * Piece.block_size()

    block_size =
      if begin + block_size > full_size do
        size(torrent) - begin
      else
        block_size
      end

    {piece_index, block_index * block_size, block_size}
  end

  def update_with_block_downloaded(torrent, piece_index, block_index, block_size) do
    pieces =
      Enum.map(torrent.pieces, fn piece ->
        if piece.number == piece_index do
          %Piece{
            piece
            | blocks: MapSet.put(piece.blocks, block_index)
          }
        else
          piece
        end
      end)

    %Torrent{torrent | pieces: pieces, downloaded: torrent.downloaded + block_size}
  end
end
