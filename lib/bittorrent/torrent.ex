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

  alias Bittorrent.{Torrent, TrackerInfo}

  def update_with_tracker_info(%Torrent{} = torrent, port) do
    info = TrackerInfo.for_torrent(torrent, port)
    %Torrent{torrent | peers: info.peers}
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  def blocks_we_need_that_peer_has(pieces, piece_set) do
    pieces
    |> Enum.filter(fn piece -> Enum.at(piece_set, piece.number) end)
    |> Enum.flat_map(fn piece -> blocks_we_need_in_piece(piece) end)
  end

  defp blocks_we_need_in_piece(piece) do
    piece.blocks
    |> Enum.with_index()
    |> Enum.reject(fn {we_have_block?, _block_index} -> we_have_block? end)
    |> Enum.map(fn {_we_have_block?, block_index} -> {piece.number, block_index} end)
  end

  def request_for_block(torrent, piece_index, block_index) do
    block_size = Bittorrent.Piece.block_size()
    full_size = size(torrent)
    begin = block_index * Bittorrent.Piece.block_size()

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
          %Bittorrent.Piece{
            piece
            | blocks: List.replace_at(piece.blocks, block_index, true)
          }
        else
          piece
        end
      end)

    %Torrent{torrent | pieces: pieces, downloaded: torrent.downloaded + block_size}
  end
end
