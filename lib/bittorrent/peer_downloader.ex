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

  @type peer() :: %Peer.State{} | nil
  @type peer_downloader() :: %State{
          peer: peer()
        }

  # Client

  def start_link({info_sha, peer_id, address}) do
    GenServer.start_link(__MODULE__, {info_sha, peer_id, address})
  end

  # Server

  @impl true
  def init({info_sha, peer_id, nil}) do
    sleep()

    {:ok,
     %State{
       info_sha: info_sha,
       peer_id: peer_id
     }}
  end

  @impl true
  def init({info_sha, peer_id, address}) do
    state = %State{
      info_sha: info_sha,
      peer_id: peer_id,
      address: address
    }

    start_handshake_task_or_sleep(state)

    {:ok, state}
  end

  @impl true
  def handle_info({_task, {:connected, peer, socket}}, state) do
    Logger.debug("PeerDownloader: connected")
    Logger.metadata(peer: Base.encode64(peer.id))

    state = %State{
      state
      | address: Peer.Address.just_connected(state.address),
        peer: peer,
        socket: socket
    }

    {:noreply, request_piece(state)}
  end

  @impl true
  def handle_info({_task, {:downloaded, piece, peer}}, state) do
    Logger.debug("PeerDownloader: piece complete, fetching next piece")
    Client.piece_downloaded(state.peer.piece.number, piece)
    state = %State{state | peer: peer}

    {:noreply, request_piece(state)}
  end

  @impl true
  def handle_info({_task, {:error, address, reason}}, state) do
    Logger.debug("PeerDownloader: new connection because error #{reason}")
    Client.return_peer(address)

    state = %State{
      state
      | address: request_peer(),
        peer: state.peer && %Peer.State{state.peer | piece: nil},
        socket: nil
    }

    start_handshake_task_or_sleep(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, %State{address: nil} = state) do
    state = %State{state | address: request_peer()}
    start_handshake_task_or_sleep(state)
    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, state) do
    start_handshake_task_or_sleep(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(_, state), do: {:noreply, state}

  defp start_handshake_task_or_sleep(%State{socket: nil, address: nil}) do
    Logger.debug("PeerDownloader: no peer available, sleeping")
    sleep()
  end

  defp start_handshake_task_or_sleep(%State{socket: nil} = state) do
    start_handshake_task(state)
  end

  defp sleep() do
    Process.send_after(self(), :retry_connect, 30 * 1000)
  end

  defp start_handshake_task(state) do
    pid = self()

    Task.async(fn ->
      case Peer.connect(
             state.address,
             state.info_sha,
             state.peer_id
           ) do
        {:ok, connected_peer, socket} ->
          # Hand ownership to the PeerDownloader so the socket isn't closed by the Task ending
          :gen_tcp.controlling_process(socket, pid)

          {:connected, connected_peer, socket}

        {:error, reason} ->
          {:error, Peer.Address.just_connected(state.address), reason}
      end
    end)
  end

  defp start_download_piece_task(state) do
    Task.async(fn ->
      Logger.metadata(peer: Base.encode64(state.peer.id))
      Logger.debug("Peer: downloading piece #{state.peer.piece.number}")

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
    piece = Client.request_piece(state.peer.piece_set)

    state = %State{
      state
      | peer: %Peer.State{state.peer | piece: piece}
    }

    start_download_piece_task(state)

    state
  end
end
