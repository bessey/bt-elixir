defmodule Bittorrent.PeerDownloader do
  @moduledoc """
  Server in charge of maintaining a connection with a single Peer and downloading blocks from them
  """

  require Logger
  use GenServer
  alias Bittorrent.{Client, Peer, Peer}

  defmodule State do
    defstruct [
      # Torrent Info
      :info_sha,
      :peer_id,
      # Peer State
      address: nil,
      peer: nil,
      socket: nil
    ]
  end

  # Client

  def start_link(%State{} = state) do
    GenServer.start_link(__MODULE__, state)
  end

  def get_piece(pid) do
    GenServer.call(pid, :get_piece)
  end

  # Server

  @impl true
  def init(%State{} = state) do
    state = %State{state | address: request_peer()}
    start_connect_task_or_sleep(state)

    {:ok, state}
  end

  @impl true
  def handle_call(:get_piece, _from, state) do
    {:reply, state.peer.piece, state}
  end

  @impl true
  def handle_info({_task, {:connected, peer}}, state) do
    Logger.debug("PeerDownloader: connected")

    state =
      %State{
        state
        | address: Peer.Address.just_connected(state.address),
          peer: peer
      }
      |> request_piece()

    {:noreply, state}
  end

  @impl true
  def handle_info({_task, {:downloaded, piece, peer}}, state) do
    Logger.debug("PeerDownloader: piece complete, fetching next piece")
    Client.piece_downloaded(state.piece, piece)

    {:noreply, request_piece(%State{state | peer: peer})}
  end

  @impl true
  def handle_info({_task, {:error, address, reason}}, state) do
    Logger.debug("PeerDownloader: new connection because error #{reason}")
    Client.return_peer(address)

    state = %State{state | address: request_peer(), peer: %Peer.State{state.peer | piece: nil}}
    start_connect_task_or_sleep(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, %State{address: nil} = state) do
    state = %State{state | address: request_peer()}
    start_connect_task_or_sleep(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, state) do
    start_connect_task_or_sleep(state)
    {:noreply, state}
  end

  defp start_connect_task_or_sleep(%State{socket: nil, address: nil}) do
    Logger.debug("PeerDownloader: no peer available, sleeping")
    Process.send_after(self(), :retry_connect, 30 * 1000)
  end

  defp start_connect_task_or_sleep(%State{socket: nil} = state) do
    start_connect_task(state)
  end

  defp start_connect_task(state) do
    Task.async(fn ->
      case Peer.connect(
             state.address,
             state.info_sha,
             state.peer_id
           ) do
        {:ok, connected_peer, socket} ->
          {:connected, connected_peer, socket}

        {:error, reason} ->
          {:error, Peer.Address.just_connected(state.address), reason}
      end
    end)
  end

  defp start_download_piece_task(state) do
    Task.async(fn ->
      case Peer.download_loop(state.peer, state.socket) do
        {:error, reason} ->
          {:error, state.address, reason}

        {:ok, piece, peer} ->
          {:downloaded, piece, peer}
      end
    end)
  end

  defp request_peer() do
    {:ok, peer} = Client.request_peer()
    peer
  end

  defp request_piece(state) do
    piece = Client.request_piece(state)

    %State{
      state
      | peer: %Peer.State{state.peer | piece: piece}
    }
    |> start_download_piece_task()
  end
end
