defmodule Bittorrent.Torrent do
  @moduledoc """
  A piece, as defined in the BitTorrent protocol. A torrent is made up of a fixed number of pieces of an equal fixed size.
  """
  require Logger

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
    peer_downloaders: %{}
  ]

  alias Bittorrent.{Torrent, TrackerInfo, Piece}

  def update_with_tracker_info(%Torrent{} = torrent, port) do
    info = TrackerInfo.for_torrent(torrent, port)
    %Torrent{torrent | peers: info.peers}
  end

  def size(%Torrent{} = torrent) do
    List.first(torrent.files).size
  end

  def pieces_we_need_that_peer_has(torrent, their_piece_set) do
    torrent.pieces
    |> Enum.reject(fn our_piece -> our_piece.have end)
    |> Enum.filter(fn our_piece -> MapSet.member?(their_piece_set, our_piece.number) end)
    |> Enum.reject(fn our_piece ->
      Enum.member?(piece_numbers_in_flight(torrent), our_piece.number)
    end)
  end

  defp piece_numbers_in_flight(torrent) do
    torrent.peer_downloaders
    |> Map.values()
    |> Enum.map(&(&1.peer && &1.peer.piece && &1.peer.piece && &1.peer.piece.number))
    |> Enum.filter(& &1)
  end

  def update_with_piece_downloaded(torrent, piece_index) do
    %Torrent{torrent | pieces: List.update_at(torrent.pieces, piece_index, &Piece.complete(&1))}
  end
end
