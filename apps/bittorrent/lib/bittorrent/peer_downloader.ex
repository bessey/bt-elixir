defmodule Bittorrent.PeerDownloader do
  @moduledoc """
  Server in charge of maintaining a connection with a single Peer and downloading blocks from them
  """

  require Logger
  use GenServer
  alias Bittorrent.{Client, Peer.Connection}

  defmodule State do
    defstruct(address: nil, peer: nil, socket: nil)
  end

  @type peer() :: %Connection.State{} | nil
  @type peer_downloader() :: %State{
          peer: peer()
        }

  # Client

  def start_link(address) do
    GenServer.start_link(__MODULE__, address)
  end

  # Server

  @impl true
  def init(nil) do
    sleep()

    {:ok, %State{}}
  end

  @impl true
  def init(address) do
    state = %State{
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
      | peer: peer,
        socket: socket
    }

    Client.update_peer_downloader(state)

    {:noreply, state |> request_piece()}
  end

  @impl true
  def handle_info({_task, {:downloaded, piece, peer}}, state) do
    Logger.debug("PeerDownloader: piece complete, fetching next piece")
    Client.piece_downloaded(state.peer.piece, piece)
    state = %State{state | peer: peer} |> request_piece()

    Client.update_peer_downloader(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({_task, {:error, reason}}, state) do
    Logger.debug("PeerDownloader: new connection because error #{reason}")

    Client.return_peer(state.address)
    state = start_handshake_with_new_peer(state)

    Client.update_peer_downloader(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, %State{address: nil} = state) do
    state = %State{state | address: request_peer()}
    start_handshake_task_or_sleep(state)

    Client.update_peer_downloader(state)

    {:noreply, state}
  end

  @impl true
  def handle_info({_task, :retry_connect}, state) do
    start_handshake_task_or_sleep(state)

    Client.update_peer_downloader(state)

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
      %{info_sha: info_sha, peer_id: peer_id} = Client.get()

      case Connection.connect(
             state.address,
             info_sha,
             peer_id
           ) do
        {:ok, connected_peer, socket} ->
          # Hand ownership to the PeerDownloader so the socket isn't closed by the Task ending
          :gen_tcp.controlling_process(socket, pid)

          {:connected, connected_peer, socket}

        error ->
          error
      end
    end)
  end

  defp start_download_piece_task(state) do
    pid = self()

    Task.async(fn ->
      Logger.metadata(peer: Base.encode64(state.peer.id))
      Logger.debug("Peer: downloading piece #{state.peer.piece.number}")

      case Connection.main_loop(state.peer, state.socket, pid) do
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
    Client.request_piece(state.peer.piece_set)
    |> process_piece(state)
  end

  defp process_piece(nil, state) do
    Logger.debug("PeerDownloader: peer has no piece we need, returning")
    Client.return_peer(state.address)

    start_handshake_with_new_peer(state)
  end

  defp process_piece(piece, state) do
    state = %State{
      state
      | peer: %Connection.State{state.peer | piece: piece}
    }

    start_download_piece_task(state)
    state
  end

  defp start_handshake_with_new_peer(state) do
    state = %State{
      state
      | address: request_peer(),
        peer: state.peer && %Connection.State{state.peer | piece: nil},
        socket: nil
    }

    start_handshake_task_or_sleep(state)
    state
  end
end
