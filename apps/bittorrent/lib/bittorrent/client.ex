defmodule Bittorrent.Client do
  @moduledoc """
  Client in charge of downloading / uploading all the Files for a given BitTorrent
  """
  require Logger
  use GenServer
  alias Bittorrent.{Torrent, Peer, PeerDownloader, Piece}

  @max_connections 5

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

  def request_data(%Peer.Request{} = request) do
    GenServer.call(__MODULE__, {:request_data, request})
  end

  def request_bitfield() do
    GenServer.call(__MODULE__, {:request_bitfield})
  end

  def piece_downloaded(piece, data) do
    GenServer.call(__MODULE__, {:piece_downloaded, piece, data})
  end

  def get_state() do
    GenServer.call(__MODULE__, {:get_state})
  end

  # Server (callbacks)

  @impl true
  def init(%Torrent{} = torrent) do
    max_conns = min(:queue.len(torrent.peers), @max_connections)

    torrent = restore_from_progress(torrent)

    {torrent, child_processes} =
      if max_conns > 0 do
        Enum.reduce(1..max_conns, {torrent, []}, fn index, {torrent, children} ->
          {peer, torrent} = handle_request_peer(torrent)
          {torrent, [build_child(index, peer, torrent) | children]}
        end)
      else
        {torrent, []}
      end

    {:ok, _} = Supervisor.start_link(child_processes, strategy: :one_for_one)

    {:ok, torrent}
  end

  @impl true
  def handle_call({:request_peer}, _from, torrent) do
    {assigned_peer, state} = handle_request_peer(torrent)

    {:reply, {:ok, assigned_peer}, state |> broadcast_state()}
  end

  @impl true
  def handle_call({:request_data, %Peer.Request{} = request}, _from, torrent) do
    {:reply, {:ok, data_for_request(request, torrent)}, torrent}
  end

  @impl true
  def handle_call({:return_peer, address}, _from, torrent) do
    peers_with_returned = :queue.in(address, torrent.peers)

    connected_peers =
      Enum.reject(torrent.connected_peers, &(&1.ip === address.ip && &1.port === address.port))

    {:reply, :ok,
     %Torrent{
       torrent
       | peers: peers_with_returned,
         connected_peers: connected_peers
     }
     |> broadcast_state()}
  end

  @impl true
  def handle_call({:request_piece, piece_set}, _from, torrent) do
    pieces = Torrent.pieces_we_need_that_peer_has(torrent, piece_set)
    piece = pieces |> Enum.shuffle() |> List.first()

    if piece do
      {:reply, piece,
       %Torrent{torrent | in_progress_pieces: [piece.number | torrent.in_progress_pieces]}
       |> broadcast_state()}
    else
      {:reply, nil, torrent}
    end
  end

  @impl true
  def handle_call({:request_bitfield}, _from, torrent) do
    {:reply, {:ok, Peer.Protocol.pieces_to_bitfield(torrent.pieces)}, torrent}
  end

  @impl true
  def handle_call({:piece_downloaded, piece, data}, _from, torrent) do
    Logger.debug("Piece downloaded: #{piece.number}")

    case Piece.store_data(piece, data, torrent.output_path) do
      :ok ->
        {:reply, :ok,
         Torrent.update_with_piece_downloaded(
           torrent,
           piece.number
         )
         |> broadcast_state()}

      {:error, :sha_mismatch} ->
        Logger.warn("Piece SHA failure #{piece.number}")

        {:reply, {:error, :sha_mismatch},
         Torrent.update_with_piece_failed(
           torrent,
           piece.number
         )}
    end
  end

  @impl true
  def handle_call({:get_state}, _from, torrent) do
    {:reply, {:ok, torrent}, torrent}
  end

  # Utilities

  defp handle_request_peer(torrent) do
    case :queue.out(torrent.peers) do
      {{_value, assigned_peer}, remaining_peers} ->
        {assigned_peer,
         %Torrent{
           torrent
           | peers: remaining_peers,
             connected_peers: [assigned_peer | torrent.connected_peers]
         }}

      {:empty, _} ->
        {nil, torrent}
    end
  end

  defp restore_from_progress(torrent) do
    state =
      Piece.stored_piece_numbers(torrent.output_path)
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

  defp data_for_request(request, torrent) do
    piece_path = Piece.path_for_piece(torrent.output_path, request.piece)
    {:ok, file} = :file.open(piece_path, [:read, :binary])
    {:ok, contents} = :file.pread(file, request.begin, request.block_size)
    :file.close(file)
    contents
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

  defp broadcast_state(torrent) do
    BittorrentWeb.Endpoint.broadcast("torrents", "update", torrent)
    torrent
  end
end
