defmodule Bittorrent.Client do
  @moduledoc """
  Client in charge of downloading / uploading all the Files for a given BitTorrent
  """
  require Logger
  use GenServer
  alias Bittorrent.{Torrent, Peer, PeerDownloader}

  @pieces_in_progress_path "_pieces"
  @tmp_extension ".tmp"
  @max_connections 50

  def in_progress_path(), do: @pieces_in_progress_path

  # Client

  def start_link(%Torrent{} = torrent) do
    GenServer.start_link(__MODULE__, torrent, name: __MODULE__)
  end

  def request_peer() do
    GenServer.call(__MODULE__, {:request_peer})
  end

  def return_peer(address) do
    GenServer.call(__MODULE__, {:return_peer, Peer.Address.last_connected(address)})
  end

  def request_piece(piece_set) do
    GenServer.call(__MODULE__, {:request_piece, piece_set})
  end

  def piece_downloaded(piece_index, data) do
    GenServer.call(__MODULE__, {:piece_downloaded, piece_index, data})
  end

  # Server (callbacks)

  @impl true
  def init(%Torrent{} = torrent) do
    max_conns = min(:queue.len(torrent.peers), @max_connections)

    torrent = restore_from_progress(torrent)

    {torrent, child_processes} =
      Enum.reduce(1..max_conns, {torrent, []}, fn index, {torrent, children} ->
        {peer, torrent} = handle_request_peer(torrent)
        {torrent, [build_child(index, peer, torrent) | children]}
      end)

    {:ok, _} = Supervisor.start_link(child_processes, strategy: :one_for_one)

    {:ok, torrent}
  end

  @impl true
  def handle_call({:request_peer}, _from, torrent) do
    {assigned_peer, state} = handle_request_peer(torrent)

    {:reply, {:ok, assigned_peer}, state}
  end

  @impl true
  def handle_call({:return_peer, address}, _from, torrent) do
    peers_with_returned = :queue.in(address, torrent.peers)

    {:reply, :ok,
     %Torrent{
       torrent
       | peers: peers_with_returned
     }}
  end

  @impl true
  def handle_call({:request_piece, piece_set}, _from, torrent) do
    pieces = Torrent.pieces_we_need_that_peer_has(torrent, piece_set)
    piece = pieces |> Enum.shuffle() |> List.first()

    if piece do
      {:reply, piece,
       %Torrent{torrent | in_progress_pieces: [piece.number, torrent.in_progress_pieces]}}
    else
      {:reply, nil, torrent}
    end
  end

  @impl true
  def handle_call({:piece_downloaded, piece_index, data}, _from, torrent) do
    Logger.debug("Piece downloaded: #{piece_index}")

    {:reply,
     File.write(
       Path.join([
         torrent.output_path,
         @pieces_in_progress_path,
         "#{piece_index}#{@tmp_extension}"
       ]),
       data
     ),
     Torrent.update_with_piece_downloaded(
       torrent,
       piece_index
     )}
  end

  # Utilities

  defp handle_request_peer(torrent) do
    case :queue.out(torrent.peers) do
      {{_value, assigned_peer}, remaining_peers} ->
        {assigned_peer,
         %Torrent{
           torrent
           | peers: remaining_peers
         }}

      {:empty, _} ->
        {nil, torrent}
    end
  end

  defp restore_from_progress(torrent) do
    pieces_path = Path.join([torrent.output_path, @pieces_in_progress_path])
    tmp_extension_index = -(String.length(@tmp_extension) + 1)

    {:ok, existing_pieces} = File.ls(pieces_path)

    state =
      existing_pieces
      |> Enum.map(&String.slice(&1, 0..tmp_extension_index))
      |> Enum.map(&String.to_integer/1)
      |> Enum.reduce(torrent, fn piece_index, torrent ->
        Torrent.update_with_piece_downloaded(torrent, piece_index)
      end)

    Logger.info(
      "We already downloaded #{Enum.filter(state.pieces, & &1.have) |> length()}/#{
        length(state.pieces)
      } pieces :)"
    )

    state
  end

  defp build_child(index, peer, torrent) do
    %{
      id: index,
      start:
        {PeerDownloader, :start_link,
         [
           {
             torrent.info_sha,
             torrent.peer_id,
             peer
           }
         ]}
    }
  end
end
